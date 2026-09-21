pipeline {
    agent {
        dockerfile {
            filename 'Dockerfile'
            dir 'ci'
            label 'linux-build'
            // Build containers must share SonarQube's network for DNS resolution.
            args '--network jenkins-net'
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
            agent {
                dockerfile {
                    filename 'Dockerfile'
                    dir 'ci/playwright'
                    label 'linux-build'
                    args '--network jenkins-net -v /var/run/docker.sock:/var/run/docker.sock'
                }
            }
            environment {
                E2E_BASE_URL = 'http://nginx'
            }
            steps {
                sh '''
                    docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.e2e.yml --project-name auto-chess-e2e up -d --build

                    for attempt in $(seq 1 30); do
                      curl --fail --silent --show-error http://nginx/health/ready && break
                      sleep 2
                    done

                    curl --fail --silent --show-error http://nginx/health/ready
                    cd e2e
                    npm ci
                    npm run test:e2e
                '''
            }
            post {
                always {
                    junit 'e2e/reports/junit.xml'
                    publishHTML(target: [
                        reportDir: 'e2e/playwright-report',
                        reportFiles: 'index.html',
                        reportName: 'Playwright E2E Report',
                        keepAll: true,
                        alwaysLinkToLastBuild: true,
                    ])
                    archiveArtifacts artifacts: 'e2e/playwright-report/**', allowEmptyArchive: true
                    sh 'docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.e2e.yml --project-name auto-chess-e2e down -v --remove-orphans'
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
