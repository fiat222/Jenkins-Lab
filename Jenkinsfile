pipeline {
    agent {
        docker {
            image 'node:20-alpine'
            label 'linux-build'
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
                    sh 'npm test -- --coverage --reporters=jest-junit'
                }
            }
        }

	stage('SonarQube Analysis') {
    	    steps {
        	dir('backend') {
		    Script {
            	    	def scannerHome = tool 'sonar-scanner'
			withSonarQubeEnv('SonarQube') {
                	    sh 'sonar-scanner -Dsonar.projectKey=taskflow-api -Dsonar.sources=. -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info'
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

        stage('Deploy - Staging') {
            when { branch 'develop' }
            steps { sh 'echo deploying to staging...' }
        }
        stage('Deploy - Production') {
            when { branch 'main' }
            input { message 'Deploy to production?' }
            steps { sh 'echo deploying to production...' }
        }
    }

    post {
        success { echo "${env.APP_NAME} passed on ${env.NODE_ENV}" }
        failure { echo "Failed at stage: ${env.STAGE_NAME}" }
        always {
            junit 'backend/reports/junit.xml'
            publishCoverage adapters: [coberturaAdapter('backend/coverage/cobertura-coverage.xml')]
            archiveArtifacts artifacts: 'backend/npm-debug.log*', allowEmptyArchive: true
        }
    }
}
