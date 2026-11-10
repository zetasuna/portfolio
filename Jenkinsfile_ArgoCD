pipeline {
  // CI runs on the permanent agent service (compose.yaml: jenkins-agent),
  // built from deploy/ci/Dockerfile and labeled "docker-go" in Jenkins.
  agent { label 'docker-go' }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
    skipDefaultCheckout(true)
  }

  environment {
    IMAGE_REPO    = 'nam2107/portfolio'
    GITOPS_BRANCH = 'deploy'
    GITOPS_REPO_URL = 'https://github.com/zetasuna/portfolio.git'
    ARGOCD_HOST   = 'argocd.local'
    SMOKE_HOST    = '192.168.49.2'
    DOCKER_BUILDKIT = '1'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.IMAGE_TAG = sh(
            returnStdout: true,
            script: 'git rev-parse --short=12 HEAD'
          ).trim()
          echo "IMAGE_TAG=${env.IMAGE_TAG}  BRANCH=${env.BRANCH_NAME}"
        }
      }
    }

    stage('Format and vet') {
      steps {
        sh '''
          set -eu
          unformatted="$(gofmt -l cmd internal tests)"
          if [ -n "$unformatted" ]; then
            printf '%s\\n' "$unformatted"
            echo "Go files need formatting."
            exit 1
          fi
          go vet ./...
        '''
      }
    }

    stage('Unit tests') {
      steps {
        sh '''
          set -eu
          mkdir -p reports
          gotestsum --junitfile reports/unit.xml --format standard-verbose -- \
            -race -coverprofile=coverage.out ./...
          go tool cover -func=coverage.out | tail -n 1
        '''
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'reports/unit.xml'
          archiveArtifacts artifacts: 'coverage.out,reports/unit.xml', allowEmptyArchive: true
        }
      }
    }

    stage('Database integration tests') {
      steps {
        sh '''
          set -eu
          # lib/pq panics if these are set to unsupported service files.
          unset PGSERVICEFILE PGPASSFILE || true
          DB_HOST="${DB_HOST:-host.docker.internal}"
          if ! getent hosts "$DB_HOST" >/dev/null 2>&1; then
            echo "WARNING: $DB_HOST does not resolve; trying the default bridge gateway"
            DB_HOST=172.17.0.1
          fi
          DB_PORT="${DB_PORT:-$((20000 + (${BUILD_NUMBER:-0} % 20000)))}"
          CONTAINER="portfolio-ci-postgres-${BUILD_NUMBER:-0}"
          POSTGRES_DB=portfolio
          POSTGRES_USER=portfolio_admin
          POSTGRES_PASSWORD="$(openssl rand -hex 16)"
          APP_DB_USER=portfolio_app
          APP_DB_PASSWORD="$(openssl rand -hex 16)"
          TEST_DB_NAME=portfolio_test

          cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
          trap cleanup EXIT
          cleanup

          docker create --name "$CONTAINER" \
            -p "${DB_PORT}:5432" \
            -e POSTGRES_DB="$POSTGRES_DB" \
            -e POSTGRES_USER="$POSTGRES_USER" \
            -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
            -e APP_DB_USER="$APP_DB_USER" \
            -e APP_DB_PASSWORD="$APP_DB_PASSWORD" \
            -e TEST_DB_NAME="$TEST_DB_NAME" \
            postgres:18 >/dev/null
          docker cp deploy/postgres/init/01-app-role.sh \
            "$CONTAINER:/docker-entrypoint-initdb.d/01-app-role.sh"
          docker start "$CONTAINER" >/dev/null

          ready=false
          for _ in $(seq 1 60); do
            # The test database only exists after 01-app-role.sh has finished,
            # so this also waits for the init scripts to complete.
            if docker exec "$CONTAINER" psql -U "$POSTGRES_USER" -d "$TEST_DB_NAME" \
              -c 'select 1' >/dev/null 2>&1; then
              ready=true
              break
            fi
            sleep 2
          done
          if [ "$ready" != true ]; then
            echo "PostgreSQL did not become ready" >&2
            docker logs "$CONTAINER" >&2 || true
            exit 1
          fi

          export TEST_DATABASE_URL="postgres://${APP_DB_USER}:${APP_DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${TEST_DB_NAME}?sslmode=disable"
          go test ./tests/integration -v -count=1
        '''
      }
    }

    stage('Dependency vulnerability scan') {
      steps {
        sh '''
          set -eu
          go run golang.org/x/vuln/cmd/govulncheck@v1.1.4 ./...
        '''
      }
    }

    stage('Build image') {
      steps {
        sh '''
          set -eu
          docker build --pull -t "${IMAGE_REPO}:${IMAGE_TAG}" .
          docker image inspect "${IMAGE_REPO}:${IMAGE_TAG}" >/dev/null
        '''
      }
    }

    stage('Container image scan') {
      steps {
        sh '''
          set -eu
          # Block on CRITICAL; report HIGH without failing the build.
          trivy image --no-progress --scanners vuln --severity CRITICAL \
            --exit-code 1 "${IMAGE_REPO}:${IMAGE_TAG}"
          trivy image --no-progress --scanners vuln --severity HIGH \
            --exit-code 0 "${IMAGE_REPO}:${IMAGE_TAG}"
        '''
      }
    }

    stage('Publish image') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub',
          usernameVariable: 'DOCKERHUB_USER',
          passwordVariable: 'DOCKERHUB_TOKEN'
        )]) {
          sh '''
            set +x
            set -eu
            test -n "$DOCKERHUB_USER"
            echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USER" --password-stdin
            docker push "${IMAGE_REPO}:${IMAGE_TAG}"
            docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE_REPO}:${IMAGE_TAG}" || true
            docker logout >/dev/null 2>&1 || true
          '''
        }
      }
    }

    stage('Update GitOps branch') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'github-gitops', variable: 'GITHUB_TOKEN')]) {
          sh '''
            set +x
            set -eu
            GITOPS_PUSH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/zetasuna/portfolio.git" \
              ./scripts/ci-gitops-bump.sh "${IMAGE_TAG}"
          '''
        }
      }
    }

    stage('Wait for Argo CD') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'argocd-admin-password', variable: 'ARGOCD_PASSWORD')]) {
          sh '''
            set +x
            set -eu
            if ! getent hosts "$ARGOCD_HOST" >/dev/null 2>&1; then
              echo "ERROR: $ARGOCD_HOST does not resolve in the agent." >&2
              echo "Add argocd.local to extra_hosts in the jenkins-agent compose service." >&2
              exit 1
            fi
            argocd login "$ARGOCD_HOST" --plaintext --grpc-web \
              --username admin --password "$ARGOCD_PASSWORD"
            argocd app wait portfolio-app --sync --health --timeout 600
            argocd app wait portfolio-observability --sync --timeout 600
          '''
        }
      }
    }

    stage('Smoke test') {
      when { branch 'main' }
      steps {
        sh '''
          set -eu
          SMOKE_HOST="${SMOKE_HOST}" ./scripts/k8s-smoke.sh
        '''
      }
    }
  }

  post {
    failure {
      echo 'Pipeline failed. To roll back the app:'
      echo '  argocd app history portfolio-app'
      echo '  argocd app rollback portfolio-app <history-id>'
      echo 'or revert the GitOps branch commit with git revert.'
    }
    always {
      sh 'docker logout >/dev/null 2>&1 || true'
      cleanWs()
    }
  }
}
