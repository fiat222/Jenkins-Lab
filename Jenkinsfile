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
                        npx eslint --plugin security src/ \
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
