// Terraform runs as a sibling container sharing this workspace and reaching LocalStack on jenkins-net.
def terraform(String args, Map opts = [:]) {
    def result
    // `-e NAME` with no value forwards the bound credential without writing it into the command.
    withCredentials([usernamePassword(credentialsId: 'localstack-aws',
                                      usernameVariable: 'AWS_ACCESS_KEY_ID',
                                      passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
        result = sh(
            script: """
                docker run --rm --network jenkins-net \\
                  --volumes-from "\$HOSTNAME" --user "\$(id -u):\$(id -g)" \\
                  -v /var/run/docker.sock:/var/run/docker.sock \\
                  -e HOME=/tmp -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \\
                  -w "\$PWD/infra/terraform" \\
                  hashicorp/terraform:1.15 ${args}
            """,
            returnStdout: opts.stdout ?: false,
            returnStatus: opts.status ?: false
        )
    }
    return result
}

pipeline {
    agent none

    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        // A hung npm install or test run must not hold the executor forever
    }

    stages {
        // Cheapest gate first: stop on a leaked credential before spending any other compute.
        stage('Secrets Detection') {
            agent {
                kubernetes {
                    cloud 'kind'
                    yamlFile 'ci/k8s/pods/scan.yaml'
                    defaultContainer 'gitleaks'
                }
            }
            steps {
                sh '''
                    mkdir -p security
                    gitleaks detect --source . --config .gitleaks.toml --log-opts="--all" \
                      --report-format json --report-path security/gitleaks.json
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security/gitleaks.json', allowEmptyArchive: true
                }
            }
        }

        // Independent checks share one parallel block, each on its own pod; any failure stops the rest.
        stage('Parallel Checks') {
            failFast true
            parallel {
                stage('Lint') {
                    agent {
                        kubernetes {
                            cloud 'kind'
                            yamlFile 'ci/k8s/pods/node.yaml'
                            defaultContainer 'node'
                        }
                    }
                    steps { dir('backend') { sh 'npm ci && npm run lint' } }
                }
                stage('Unit Test') {
                    agent {
                        kubernetes {
                            cloud 'kind'
                            yamlFile 'ci/k8s/pods/node.yaml'
                            defaultContainer 'node'
                        }
                    }
                    steps { dir('backend') { sh 'npm ci && npm test -- --coverage' } }
                    post {
                        always {
                            junit 'backend/reports/junit.xml'
                            recordCoverage tools: [[parser: 'COBERTURA', pattern: 'backend/coverage/cobertura-coverage.xml']]
                            archiveArtifacts artifacts: 'backend/npm-debug.log*', allowEmptyArchive: true
                            stash name: 'unit-test-results', includes: 'backend/coverage/**,backend/reports/**', allowEmpty: true
                        }
                    }
                }
                stage('SAST') {
                    agent {
                        kubernetes {
                            cloud 'kind'
                            yamlFile 'ci/k8s/pods/scan.yaml'
                            defaultContainer 'node'
                        }
                    }
                    steps {
                        sh 'mkdir -p security && cd backend && npm ci --no-audit --no-fund'
                        script {
                            // ESLint exits 1 for findings (reported in SARIF) and >1 when the scanner itself breaks.
                            int eslintStatus = sh(returnStatus: true, script: '''
                                cd backend && npx eslint --plugin security --ext .ts src/ \
                                  --format @microsoft/eslint-formatter-sarif --output-file ../security/eslint.sarif
                            ''')
                            int semgrepStatus = 0
                            container('semgrep') {
                                semgrepStatus = sh(returnStatus: true, script: '''
                                    semgrep scan --config=p/owasp-top-ten --config=p/nodejs \
                                      --sarif --output security/semgrep.sarif .
                                ''')
                            }
                            if (eslintStatus > 1 || semgrepStatus != 0) {
                                error("SAST scanner failed: eslint=${eslintStatus} semgrep=${semgrepStatus}")
                            }
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'security/*.sarif', allowEmptyArchive: true
                        }
                    }
                }
                stage('SCA - npm audit') {
                    agent {
                        kubernetes {
                            cloud 'kind'
                            yamlFile 'ci/k8s/pods/node.yaml'
                            defaultContainer 'node'
                        }
                    }
                    steps {
                        dir('backend') {
                            script {
                                sh 'npm audit --json > audit.json || true'
                                def counts = sh(script: """node -e 'const v=require("./audit.json").metadata?.vulnerabilities; if (!v) process.exit(2); console.log([v.critical||0,v.high||0,v.moderate||0,v.low||0].join(","))'""", returnStdout: true).trim().split(',')
                                int critical = counts[0].toInteger()
                                int high = counts[1].toInteger()
                                int moderate = counts[2].toInteger()
                                int low = counts[3].toInteger()

                                echo "npm audit: critical=${critical}, high=${high}, moderate=${moderate}, low=${low}"
                                if (critical > 0) {
                                    echo 'Critical vulnerabilities found; Policy Gate will decide the build result'
                                }
                                if (high > 0 || moderate > 0 || low > 0) {
                                    echo 'SCA warning: vulnerabilities found, but no Critical issues'
                                } else {
                                    echo 'SCA passed: no vulnerabilities found'
                                }
                            }
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'backend/audit.json', allowEmptyArchive: true
                            stash name: 'npm-audit', includes: 'backend/audit.json', allowEmpty: true
                        }
                    }
                }
            }
        }

        // Scanners, image builds, deploys and IaC drive Docker through the agent's socket.
        stage('Security, Delivery & IaC') {
            agent {
                dockerfile {
                    filename 'Dockerfile'
                    dir 'ci'
                    label 'linux-build'
                    // Build containers must share SonarQube's network for DNS resolution.
                    // Docker Pipeline first supplies -u 1000:1000. The agent mounts
                    // its daemon socket as root:root (0660), so this final user value
                    // keeps UID 1000 while granting the required socket group.
                    args '--network jenkins-net -u 1000:0'
                }
            }
            stages {
                stage('Generate SBOM') {
                    steps {
                        sh '''
                            mkdir -p security
                            docker run --rm \
                                --volumes-from "$HOSTNAME" \
                                --workdir "$PWD" \
                                anchore/syft:v1.42.3 \
                                scan dir:backend \
                                -o cyclonedx-json=security/taskflow-api.cdx.json
                        '''

                        withCredentials([
                            file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY'),
                            file(credentialsId: 'cosign-public-key', variable: 'COSIGN_PUB'),
                            string(credentialsId: 'cosign-key-password', variable: 'COSIGN_PASSWORD')
                        ]) {
                            sh '''
                                docker run --rm \
                                    --user "$(id -u):$(id -g)" \
                                    --volumes-from "$HOSTNAME" \
                                    --workdir "$PWD" \
                                    --env COSIGN_PASSWORD \
                                    --env HOME=/tmp \
                                    ghcr.io/sigstore/cosign/cosign:v3.0.2 \
                                    sign-blob --yes \
                                    --key "$COSIGN_KEY" \
                                    --bundle security/taskflow-api.cdx.bundle.json \
                                    security/taskflow-api.cdx.json

                                docker run --rm \
                                    --user "$(id -u):$(id -g)" \
                                    --volumes-from "$HOSTNAME" \
                                    --workdir "$PWD" \
                                    --env HOME=/tmp \
                                    ghcr.io/sigstore/cosign/cosign:v3.0.2 \
                                    verify-blob \
                                    --key "$COSIGN_PUB" \
                                    --bundle security/taskflow-api.cdx.bundle.json \
                                    security/taskflow-api.cdx.json
                            '''
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'security/taskflow-api.cdx.json,security/taskflow-api.cdx.bundle.json',
                                allowEmptyArchive: true
                        }
                    }
                }
          
                stage('Policy Gate') {
                    steps {
                        unstash 'npm-audit'
                        sh '''
                            docker run --rm \
                                --volumes-from "$HOSTNAME" \
                                --workdir "$PWD" \
                                openpolicyagent/opa:1.0.0 \
                                eval \
                                --fail-defined \
                                --format pretty \
                                --data policy/security.rego \
                                --input backend/audit.json \
                                'data.taskflow.security.deny[_]'
                        '''
                    }
                }

                stage('SonarQube Analysis') {
                        steps {
                        unstash 'unit-test-results'
                        dir('backend') {
                        script {
                                    def scannerHome = tool 'sonar-scanner'
                        // JDK 21 is provided by the CI image, avoiding agent tool-cache permissions.
                        withEnv(['JAVA_HOME=/opt/java/openjdk', 'PATH+JAVA=/opt/java/openjdk/bin']) {
                            withSonarQubeEnv('SonarQube') {
                            // Spec files are tests, not sources; otherwise editing a test counts as uncovered new code.
                            sh "${scannerHome}/bin/sonar-scanner -Dsonar.projectKey=taskflow-api -Dsonar.sources=src -Dsonar.tests=src '-Dsonar.test.inclusions=**/*.spec.ts' '-Dsonar.exclusions=**/*.spec.ts' -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info"
                            }
                        }
                            }
                            }
                    }
                }
                stage('Quality Gate') {
                    steps {
                    timeout(time: 5, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                    }
                }

                stage('E2E') {
                    environment {
                        E2E_BASE_URL = 'http://e2e-nginx:8080'
                    }
                    steps {
                        sh '''
                            docker build --tag "taskflow-e2e:${BUILD_TAG}" --file ci/playwright/Dockerfile ci/playwright
                            docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.e2e.yml --project-name auto-chess-e2e down -v --remove-orphans || true
                            docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.e2e.yml --project-name auto-chess-e2e up -d --build postgres-primary redis nest-1 nest-2 nest-3 nginx

                            for attempt in $(seq 1 30); do
                              curl --fail --silent --show-error "$E2E_BASE_URL/health/ready" && break
                              sleep 2
                            done

                            curl --fail --silent --show-error "$E2E_BASE_URL/health/ready"
                            docker run --rm \\
                              --network jenkins-net \\
                              --volumes-from "$HOSTNAME" \\
                              --user "$(id --user):$(id --group)" \\
                              --workdir "$PWD/e2e" \\
                              --env E2E_BASE_URL \\
                              "taskflow-e2e:${BUILD_TAG}" \\
                              sh -c 'npm ci && npm run test:e2e'
                        '''
                    }
                    post {
                        always {
                            sh 'docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.e2e.yml --project-name auto-chess-e2e down -v --remove-orphans'
                            // Each build tags its own runner image; untag it so they do not pile up (3.5 GB each).
                            sh 'docker rmi "taskflow-e2e:${BUILD_TAG}" || true'
                            junit testResults: 'e2e/reports/junit.xml', allowEmptyResults: true
                            publishHTML(target: [
                                reportDir: 'e2e/playwright-report',
                                reportFiles: 'index.html',
                                reportName: 'Playwright E2E Report',
                                keepAll: true,
                                alwaysLinkToLastBuild: true,
                                allowMissing: true,
                            ])
                            archiveArtifacts artifacts: 'e2e/playwright-report/**', allowEmptyArchive: true
                        }
                    }
                }

                stage('Build Image') {
                    steps {
                        script {
                            env.IMAGE_TAG = "localhost:5001/taskflow-api:${env.GIT_COMMIT.take(7)}"
                        }
                        sh "docker build -t ${env.IMAGE_TAG} backend"
                        sh "docker push ${env.IMAGE_TAG}"
                    }
                }

                stage('Container Scan') {
                    steps {
                        sh """
                            docker run --rm \
                              -v /var/run/docker.sock:/var/run/docker.sock \
                              --volumes-from "\$HOSTNAME" \
                              aquasec/trivy image \
                              --exit-code 1 --severity HIGH,CRITICAL \
                              --format sarif -o "\$PWD/trivy-taskflow-api.sarif" \
                              ${env.IMAGE_TAG}
                        """
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'trivy-taskflow-api.sarif', allowEmptyArchive: true
                        }
                    }
                }

                stage('Blue/Green Deploy') {
                    steps {
                        withCredentials([file(credentialsId: 'kind-kubeconfig', variable: 'KUBECONFIG')]) {
                            script {
                                env.CURRENT_COLOR = sh(
                                    script: "kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'",
                                    returnStdout: true
                                ).trim()
                                env.NEXT_COLOR = env.CURRENT_COLOR == 'blue' ? 'green' : 'blue'

                                sh "kubectl set image deployment/taskflow-${env.NEXT_COLOR} app=${env.IMAGE_TAG}"
                                sh "kubectl rollout status deployment/taskflow-${env.NEXT_COLOR} --timeout=120s"

                                // smoke test the new pods directly, bypassing the main Service
                                sh "kubectl run smoke-${BUILD_NUMBER} --rm -i --restart=Never --image=curlimages/curl -- curl -sf http://taskflow-${env.NEXT_COLOR}:8080/health/live"

                                sh "kubectl patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${env.NEXT_COLOR}\"}}}'"
                                echo "Switched traffic from ${env.CURRENT_COLOR} to ${env.NEXT_COLOR}"
                            }
                        }
                    }
                    post {
                        failure {
                            script {
                                // Patching with an unset color would point the Service at no pods.
                                if (['blue', 'green'].contains(env.CURRENT_COLOR)) {
                                    withCredentials([file(credentialsId: 'kind-kubeconfig', variable: 'KUBECONFIG')]) {
                                        sh "kubectl patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${env.CURRENT_COLOR}\"}}}'"
                                        sh "kubectl rollout undo deployment/taskflow-${env.NEXT_COLOR} || true"
                                        echo "ROLLBACK: traffic kept on ${env.CURRENT_COLOR}"
                                    }
                                } else {
                                    echo 'ROLLBACK skipped: current color was never read, Service left untouched'
                                }
                            }
                        }
                    }
                }

                stage('IaC Lint & Validate') {
                    parallel {
                        stage('Terraform Validate') {
                            steps {
                                script {
                                    terraform 'init -backend=false -input=false -no-color'
                                    terraform 'validate -no-color'
                                    terraform 'fmt -check -recursive'
                                }
                            }
                        }
                        stage('Ansible Lint') {
                            steps {
                                sh 'docker build -t taskflow-ansible:ci ci/ansible'
                                sh 'docker run --rm --volumes-from "$HOSTNAME" --user "$(id -u):$(id -g)" -w "$PWD" taskflow-ansible:ci ansible-lint --offline infra/ansible/playbook.yml'
                            }
                        }
                    }
                }

                stage('IaC Security Scan') {
                    steps {
                        sh '''
                            mkdir -p security
                            rc=0
                            docker run --rm --volumes-from "$HOSTNAME" --user "$(id -u):$(id -g)" -e HOME=/tmp \
                              aquasec/tfsec:latest "$PWD/infra/terraform" --no-color --out "$PWD/security/tfsec.txt" || rc=1
                            docker run --rm --volumes-from "$HOSTNAME" --user "$(id -u):$(id -g)" -e HOME=/tmp \
                              bridgecrew/checkov:latest -d "$PWD/infra/terraform" --framework terraform --compact --quiet --skip-download \
                              > security/checkov.txt 2>&1 || rc=1
                            cat security/checkov.txt
                            exit $rc
                        '''
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'security/tfsec.txt, security/checkov.txt', allowEmptyArchive: true
                        }
                    }
                }

                stage('Terraform Plan') {
                    when { branch 'main' }
                    steps {
                        // LocalStack community keeps no data across restarts, so recreate the state bucket if needed.
                        withCredentials([usernamePassword(credentialsId: 'localstack-aws',
                                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                            sh '''
                                docker run --rm --network jenkins-net --entrypoint sh \
                                  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=us-east-1 \
                                  amazon/aws-cli -c 'aws --endpoint-url http://localstack:4566 s3api head-bucket --bucket taskflow-tfstate \
                                    || aws --endpoint-url http://localstack:4566 s3 mb s3://taskflow-tfstate'
                            '''
                        }
                        script {
                            terraform 'init -reconfigure -input=false -no-color'
                            def rc = terraform('plan -input=false -no-color -detailed-exitcode -out=tfplan', [status: true])
                            if (rc == 1) {
                                error('terraform plan failed')
                            }
                            env.TF_CHANGES = rc == 2 ? 'true' : 'false'
                            writeFile file: 'infra/terraform/tfplan.txt', text: terraform('show -no-color tfplan', [stdout: true])
                            echo "Terraform changes pending: ${env.TF_CHANGES}"
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'infra/terraform/tfplan, infra/terraform/tfplan.txt', allowEmptyArchive: true
                        }
                    }
                }

                stage('Approval') {
                    when {
                        branch 'main'
                        environment name: 'TF_CHANGES', value: 'true'
                    }
                    steps {
                        script {
                            def summary = sh(script: "grep -E '^(Plan:|  # )' infra/terraform/tfplan.txt || true", returnStdout: true).trim()
                            timeout(time: 15, unit: 'MINUTES') {
                                input message: "Apply this Terraform plan?\n\n${summary}", ok: 'Apply'
                            }
                        }
                    }
                }

                stage('Terraform Apply') {
                    when {
                        branch 'main'
                        environment name: 'TF_CHANGES', value: 'true'
                    }
                    steps {
                        script {
                            terraform 'apply -input=false -no-color tfplan'
                            terraform 'output -no-color'
                        }
                    }
                }

                stage('Configure with Ansible') {
                    when { branch 'main' }
                    steps {
                        script {
                            def host = terraform('output -raw host_name', [stdout: true]).trim()
                            writeFile file: 'infra/ansible/inventory.ini',
                                      text: "[taskflow]\n${host} ansible_connection=community.docker.docker_api\n"
                        }
                        sh """
                            docker run --rm --network jenkins-net \\
                              --volumes-from "\$HOSTNAME" --user "\$(id -u):\$(id -g)" \\
                              -v /var/run/docker.sock:/var/run/docker.sock \\
                              -e TASKFLOW_IMAGE=${env.IMAGE_TAG} -w "\$PWD/infra/ansible" \\
                              taskflow-ansible:ci ansible-playbook -i inventory.ini playbook.yml
                        """
                    }
                }

                stage('Deploy - Staging') {
                    when { branch 'develop' }
                    steps { sh 'echo deploying to staging...' }
                }
                stage('Deploy - Production') {
                    when {
                        beforeInput true
                        branch 'main'
                    }
                    input { message 'Deploy to production?' }
                    steps { sh 'echo deploying to production...' }
                }
            }
        }
    }

    post {
        success { echo "${env.APP_NAME} passed on ${env.NODE_ENV}" }
        failure { echo "Failed at stage: ${env.STAGE_NAME}" }
    }
}
