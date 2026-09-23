pipeline {
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

    environment {
        APP_NAME = 'taskflow-api'
        NODE_ENV = 'test'
    }

    options {
        timeout(time: 10, unit: 'MINUTES')
        // A hung npm install or test run must not hold the executor forever
    }

    stages {
	stage('Secrets Detection') {
      	    steps {
          	sh '''
              	    mkdir -p security
              	    docker run --rm \
                    --volumes-from "$HOSTNAME" \
                    --workdir "$PWD" \
                    zricethezav/gitleaks:v8.21.2 \
                    detect \
                    --source . \
                    --config .gitleaks.toml \
                    --log-opts="--all" \
                    --report-format json \
                    --report-path security/gitleaks.json
          	'''
      	    }
      	    post {
          	always {
              	    archiveArtifacts artifacts: 'security/gitleaks.json', allowEmptyArchive: true
          	}
      	    }
  	}

        stage('Install') {
            steps { dir('backend') { sh 'npm ci' } }
        }
        stage('Lint') {
            steps { dir('backend') { sh 'npm run lint' } }
        }
        stage('Unit Test') {
            steps {
                dir('backend') {
                    sh 'npm test -- --coverage'
                }
            }
        }
        stage('SAST') {
            steps {
                sh '''
                    mkdir -p security

                    set +e
                    (
                        cd backend
                        npx eslint --plugin security --ext .ts src/ \
                        --format @microsoft/eslint-formatter-sarif \
                        --output-file ../security/eslint.sarif
                    )
                    eslint_status=$?

                    docker run --rm \
                        --volumes-from "$HOSTNAME" \
                        --workdir "$PWD" \
                        returntocorp/semgrep:1.95.0 \
                        semgrep scan \
                        --config=p/owasp-top-ten \
                        --config=p/nodejs \
                        --sarif \
                        --output security/semgrep.sarif \
                        .
                    semgrep_status=$?
                    set -e

                    if [ "$eslint_status" -gt 1 ] || [ "$semgrep_status" -ne 0 ]; then
                        echo "SAST scanner failed: eslint=$eslint_status semgrep=$semgrep_status"
                        exit 1
                    fi
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security/*.sarif', allowEmptyArchive: true
                }
            }
        }

        stage('SCA - npm audit') {
            steps {
                dir('backend') {
                    script {
                        sh 'npm audit --json > audit.json || true'

                        def audit = readJSON file: 'audit.json'
                        def vulnerabilities = audit.metadata?.vulnerabilities
                        if (vulnerabilities == null) {
                            error('npm audit did not return vulnerability metadata')
                        }

                        int critical = vulnerabilities.critical ?: 0
                        int high = vulnerabilities.high ?: 0
                        int moderate = vulnerabilities.moderate ?: 0
                        int low = vulnerabilities.low ?: 0

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
                }
            }
        }

        stage('Generate SBOM') {
            steps {
                sh '''
                    mkdir -p security
                    docker run --rm \
                        --volumes-from "$HOSTNAME" \
                        --workdir "$PWD" \
                        anchore/syft:v1.42.3 \
                        scan dir:backend \
                        -o cyclonedx-json=security/
                        taskflow-api.cdx.json
                '''

                withCredentials([
                    file(credentialsId: 'cosign-private-
                    key', variable: 'COSIGN_KEY'),
                    file(credentialsId: 'cosign-public-
                    key', variable: 'COSIGN_PUB'),
                    string(credentialsId: 'cosign-key-
                    password', variable:
                    'COSIGN_PASSWORD')
                ]) {
                    sh '''
                        docker run --rm \
                            --volumes-from "$HOSTNAME" \
                            --workdir "$PWD" \
                            --env COSIGN_PASSWORD \
                            ghcr.io/sigstore/cosign/cosign:v3.0.2 \
                            sign-blob --yes \
                            --key "$COSIGN_KEY" \
                            --bundle security/taskflow-
                            api.cdx.bundle.json \
                            security/taskflow-api.cdx.json

                        docker run --rm \
                            --volumes-from "$HOSTNAME" \
                            --workdir "$PWD" \
                            ghcr.io/sigstore/cosign/cosign:v3.0.2 \
                            verify-blob \
                            --key "$COSIGN_PUB" \
                            --bundle security/taskflow-
                            api.cdx.bundle.json \
                            security/taskflow-api.cdx.json
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security/
                    taskflow-api.cdx.json,security/
                    taskflow-api.cdx.bundle.json',
                        allowEmptyArchive: true
                }
            }
        }
          
        stage('Policy Gate') {
            steps {
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
                dir('backend') {
                script {
                            def scannerHome = tool 'sonar-scanner'
                // JDK 21 is provided by the CI image, avoiding agent tool-cache permissions.
                withEnv(['JAVA_HOME=/opt/java/openjdk', 'PATH+JAVA=/opt/java/openjdk/bin']) {
                    withSonarQubeEnv('SonarQube') {
                    sh "${scannerHome}/bin/sonar-scanner -Dsonar.projectKey=taskflow-api -Dsonar.sources=. -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info"
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
                E2E_BASE_URL = 'http://e2e-nginx'
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

    post {
        success { echo "${env.APP_NAME} passed on ${env.NODE_ENV}" }
        failure { echo "Failed at stage: ${env.STAGE_NAME}" }
        always {
            junit 'backend/reports/junit.xml'
            recordCoverage tools: [[parser: 'COBERTURA', pattern: 'backend/coverage/cobertura-coverage.xml']]
            archiveArtifacts artifacts: 'backend/npm-debug.log*', allowEmptyArchive: true
        }
    }
}
