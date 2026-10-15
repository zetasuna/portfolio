pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 15, unit: 'MINUTES')
    }

    tools {
        go 'go1.26.8'
    }

    environment {
        GOFLAGS = '-mod=readonly'
        CGO_ENABLED = '0'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Go Format Check') {
            steps {
                sh '''
                    files="$(gofmt -l $(find cmd internal -type f -name '*.go'))"
                    if [ -n "$files" ]; then
                        echo "The following files need gofmt:"
                        echo "$files"
                        exit 1
                    fi
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh 'go test ./...'
            }
        }

        stage('Go Vet') {
            steps {
                sh 'go vet ./...'
            }
        }

        // stage('Dependency Vulnerability Scan') {
        //     steps {
        //         sh '''
        //             go run golang.org/x/vuln/cmd/govulncheck@latest ./...
        //         '''
        //     }
        // }
    }

    post {
        always {
            echo 'CI pipeline finished. Check stage results above.'
        }
    }
}

