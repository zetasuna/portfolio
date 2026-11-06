# CI agent image

`deploy/ci/Dockerfile` builds the permanent Jenkins agent used by the pipeline
(compose service `jenkins-agent`). It is based on `jenkins/inbound-agent` and
adds Go 1.27.2, Docker CLI + buildx, Trivy, kustomize, `argocd`, `gotestsum`,
git and curl.

```bash
./scripts/publish-ci-image.sh   # optional: publish for reuse elsewhere
# or let compose build it:
docker compose --env-file .env --profile ci up -d --build jenkins-agent
```

## Register the agent

1. **Manage Jenkins → Nodes → New node**
   - Name: `ci-agent` (match `JENKINS_AGENT_NAME` in `.env`)
   - Type: Permanent Agent
   - Remote root directory: `/home/jenkins/agent`
   - Labels: `docker-go`
   - Usage: Only build jobs with label `docker-go`
   - Launch method: **Launch agent by connecting it to the controller**
2. Copy the generated secret into `.env`:
   ```bash
   JENKINS_AGENT_SECRET=<secret>
   ```
3. Start the agent:
   ```bash
   docker compose --env-file .env --profile ci up -d --build jenkins-agent
   ```
4. Confirm the node is online in **Manage Jenkins → Nodes**.

The service already has the mounts the pipeline needs:

| Mount / arg | Why |
| --- | --- |
| `/var/run/docker.sock` | build/push images, run the temporary PostgreSQL |
| `host.docker.internal:host-gateway` | integration tests reach the published PostgreSQL port |
| `argocd.local:192.168.49.2` | `argocd` CLI reaches the ingress (update if `minikube ip` changes) |
| `user: root` | needed for the mounted Docker socket |

The agent workspace is the `jenkins_agent_work` volume, so Docker builds send
their context through the Docker API and do not depend on host path mapping
(the problem the old `HOST_WORKSPACE` logic worked around).

The agent needs outbound internet for Go modules, the Trivy database and
Docker Hub.
