pipeline {
    agent any
    
    // Pipeline parameters
    parameters {
        string(
            name: 'BRANCH',
            defaultValue: 'main',
            description: 'Git branch to build'
        )
        choice(
            name: 'DEPLOY_ENV',
            choices: ['staging', 'production'],
            description: 'Deployment environment'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip test execution'
        )
        booleanParam(
            name: 'PUSH_TO_REGISTRY',
            defaultValue: false,
            description: 'Push Docker image to registry'
        )
    }
    
    // Environment variables
    environment {
        // Git and versioning
        GIT_COMMIT_SHORT = sh(
            script: "git rev-parse --short HEAD || echo 'unknown'",
            returnStdout: true
        ).trim()
        BUILD_VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
        
        // Application details
        APP_NAME = 'spring-petclinic'
        DOCKER_IMAGE = "${APP_NAME}:${BUILD_VERSION}"
        DOCKER_LATEST = "${APP_NAME}:latest"
        
        // Docker registry (configure as needed)
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_CREDENTIALS_ID = 'dockerhub-credentials'
        
        // Paths
        ARTIFACT_DIR = "${JENKINS_HOME}/artifacts/${JOB_NAME}/${BUILD_NUMBER}"
        MAVEN_OPTS = '-Dmaven.test.failure.ignore=false'
        
        // Email settings
        EMAIL_RECIPIENTS = 'devops-team@company.com'
    }
    
    // Build options
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "=========================================="
                    echo "Stage 1: Checkout Code"
                    echo "Branch: ${params.BRANCH}"
                    echo "Build Version: ${BUILD_VERSION}"
                    echo "=========================================="
                }
                
                // Checkout code from GitHub
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "*/${params.BRANCH}"]],
                    userRemoteConfigs: [[
                        url: 'https://github.com/spring-projects/spring-petclinic.git'
                    ]]
                ])
                
                // Display commit information
                sh '''
                    echo "Git Commit: $(git rev-parse HEAD)"
                    echo "Git Author: $(git log -1 --pretty=format:'%an')"
                    echo "Git Message: $(git log -1 --pretty=format:'%s')"
                '''
            }
        }
        
        stage('Build') {
            steps {
                script {
                    echo "=========================================="
                    echo "Stage 2: Maven Build"
                    echo "Build Version: ${BUILD_VERSION}"
                    echo "=========================================="
                }
                
                // Clean and build with Maven
                withMaven(maven: 'M3_HOME') { // <-- Use the name from Global Tool Config
            sh 'mvn clean package -DskipTests'
            echo "Build completed successfully"
            sh 'ls -lh target/*.jar' // Use sh separately for better Groovy variable expansion
        }
        }}
        
        stage('Parallel Testing') {
            when {
                expression { return !params.SKIP_TESTS }
            }
            parallel {
                stage('Unit Tests') {
                    steps {
                        script {
                            echo "=========================================="
                            echo "Running Unit Tests"
                            echo "=========================================="
                        }
                        
                        sh '''
                            mvn test -Dtest=**/*Test
                        '''
                    }
                    post {
                        always {
                            // Publish unit test results
                            junit testResults: '**/target/surefire-reports/*.xml',
                                  allowEmptyResults: false,
                                  skipPublishingChecks: false
                        }
                    }
                }
                
                stage('Integration Tests') {
                    steps {
                        script {
                            echo "=========================================="
                            echo "Running Integration Tests"
                            echo "=========================================="
                        }
                        
                        sh '''
                            mvn verify -DskipUnitTests=true
                        '''
                    }
                    post {
                        always {
                            // Publish integration test results
                            junit testResults: '**/target/failsafe-reports/*.xml',
                                  allowEmptyResults: true,
                                  skipPublishingChecks: false
                        }
                    }
                }
                
                stage('Code Quality Analysis') {
                    steps {
                        script {
                            echo "=========================================="
                            echo "Code Quality Checks"
                            echo "=========================================="
                        }
                        
                        sh '''
                            echo "Running code quality checks..."
                            mvn checkstyle:check || true
                            echo "Code quality analysis completed"
                        '''
                    }
                }
            }
        }
        
        stage('Docker Image Build') {
            steps {
                script {
                    echo "=========================================="
                    echo "Stage 4: Building Docker Image"
                    echo "Image: ${DOCKER_IMAGE}"
                    echo "=========================================="
                }
                
                // Create Dockerfile if it doesn't exist
                sh '''
                    if [ ! -f Dockerfile ]; then
                        cat > Dockerfile << 'EOF'
FROM openjdk:17-jdk-slim
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
                        echo "Dockerfile created"
                    fi
                '''
                
                // Build Docker image
                sh """
                    docker build -t ${DOCKER_IMAGE} .
                    docker tag ${DOCKER_IMAGE} ${DOCKER_LATEST}
                    echo "Docker image built successfully"
                    docker images | grep ${APP_NAME}
                """
            }
        }
        
        stage('Push to Registry') {
            when {
                expression { return params.PUSH_TO_REGISTRY }
            }
            steps {
                script {
                    echo "=========================================="
                    echo "Pushing Docker Image to Registry"
                    echo "=========================================="
                    
                    // Push to Docker Hub (requires credentials)
                    withCredentials([usernamePassword(
                        credentialsId: "${DOCKER_CREDENTIALS_ID}",
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh '''
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                            docker tag ${DOCKER_IMAGE} ${DOCKER_USER}/${DOCKER_IMAGE}
                            docker push ${DOCKER_USER}/${DOCKER_IMAGE}
                            docker logout
                        '''
                    }
                }
            }
        }
        
        stage('Artifact Archiving') {
            steps {
                script {
                    echo "=========================================="
                    echo "Stage 5: Archiving Artifacts"
                    echo "Artifact Version: ${BUILD_VERSION}"
                    echo "=========================================="
                }
                
                // Archive JAR files
                archiveArtifacts artifacts: 'target/*.jar',
                                fingerprint: true,
                                allowEmptyArchive: false
                
                // Create artifact directory and save metadata
                sh """
                    mkdir -p ${ARTIFACT_DIR}
                    cp target/*.jar ${ARTIFACT_DIR}/${APP_NAME}-${BUILD_VERSION}.jar
                    
                    # Create metadata file
                    cat > ${ARTIFACT_DIR}/build-info.txt << EOF
Build Number: ${BUILD_NUMBER}
Build Version: ${BUILD_VERSION}
Git Commit: ${GIT_COMMIT_SHORT}
Branch: ${params.BRANCH}
Build Date: \$(date)
Docker Image: ${DOCKER_IMAGE}
EOF
                    
                    echo "Artifact saved to: ${ARTIFACT_DIR}"
                    cat ${ARTIFACT_DIR}/build-info.txt
                """
                
                // Save Docker image as tar
                sh """
                    docker save ${DOCKER_IMAGE} -o ${ARTIFACT_DIR}/${APP_NAME}-${BUILD_VERSION}.tar
                    gzip ${ARTIFACT_DIR}/${APP_NAME}-${BUILD_VERSION}.tar
                    echo "Docker image archived"
                """
            }
        }
        
        stage('Deployment Simulation') {
            when {
                allOf {
                    expression { return params.DEPLOY_ENV == 'staging' }
                    expression { return env.CHANGE_ID == null } // Not a PR
                }
            }
            steps {
                script {
                    echo "=========================================="
                    echo "Stage 6: Deploying to ${params.DEPLOY_ENV}"
                    echo "=========================================="
                }
                
                // Create Docker network if it doesn't exist
                sh '''
                    docker network create petclinic-network || true
                '''
                
                // Stop and remove existing container
                sh """
                    docker stop ${APP_NAME} || true
                    docker rm ${APP_NAME} || true
                """
                
                // Deploy new container
                sh """
                    docker run -d \
                        --name ${APP_NAME} \
                        --network petclinic-network \
                        -p 8080:8080 \
                        -e SPRING_PROFILES_ACTIVE=${params.DEPLOY_ENV} \
                        ${DOCKER_IMAGE}
                    
                    echo "Waiting for application to start..."
                    sleep 10
                    
                    # Health check
                    if docker ps | grep ${APP_NAME}; then
                        echo "✓ Application deployed successfully!"
                        echo "✓ Container is running"
                        echo "✓ Access URL: http://localhost:8080"
                    else
                        echo "✗ Deployment failed!"
                        exit 1
                    fi
                """
                
                // Display deployment info
                sh """
                    echo "=========================================="
                    echo "Deployment Information"
                    echo "=========================================="
                    echo "Environment: ${params.DEPLOY_ENV}"
                    echo "Version: ${BUILD_VERSION}"
                    echo "Image: ${DOCKER_IMAGE}"
                    echo "Container: ${APP_NAME}"
                    echo "=========================================="
                    docker ps | grep ${APP_NAME}
                """
            }
        }
    }
    
    post {
        always {
            script {
                echo "=========================================="
                echo "Pipeline Execution Summary"
                echo "=========================================="
                echo "Job: ${JOB_NAME}"
                echo "Build: ${BUILD_NUMBER}"
                echo "Status: ${currentBuild.result ?: 'SUCCESS'}"
                echo "Duration: ${currentBuild.durationString}"
                echo "=========================================="
            }
            
            // Clean workspace
            cleanWs(
                deleteDirs: true,
                patterns: [
                    [pattern: 'target/**', type: 'INCLUDE'],
                    [pattern: '.m2/**', type: 'INCLUDE']
                ]
            )
        }
        
        success {
            script {
                echo "✓ Build completed successfully!"
                
                // Send success email
                emailext(
                    subject: "✓ SUCCESS: ${JOB_NAME} - Build #${BUILD_NUMBER}",
                    body: """
                        <html>
                        <body>
                            <h2 style="color: green;">Build Successful ✓</h2>
                            <p><strong>Job:</strong> ${JOB_NAME}</p>
                            <p><strong>Build Number:</strong> ${BUILD_NUMBER}</p>
                            <p><strong>Version:</strong> ${BUILD_VERSION}</p>
                            <p><strong>Branch:</strong> ${params.BRANCH}</p>
                            <p><strong>Environment:</strong> ${params.DEPLOY_ENV}</p>
                            <p><strong>Duration:</strong> ${currentBuild.durationString}</p>
                            <p><strong>Git Commit:</strong> ${GIT_COMMIT_SHORT}</p>
                            <hr>
                            <p><a href="${BUILD_URL}">View Build Details</a></p>
                            <p><a href="${BUILD_URL}artifact/">View Artifacts</a></p>
                        </body>
                        </html>
                    """,
                    to: "${EMAIL_RECIPIENTS}",
                    mimeType: 'text/html'
                )
            }
        }
        
        failure {
            script {
                echo "✗ Build failed!"
                
                // Send failure email
                emailext(
                    subject: "✗ FAILURE: ${JOB_NAME} - Build #${BUILD_NUMBER}",
                    body: """
                        <html>
                        <body>
                            <h2 style="color: red;">Build Failed ✗</h2>
                            <p><strong>Job:</strong> ${JOB_NAME}</p>
                            <p><strong>Build Number:</strong> ${BUILD_NUMBER}</p>
                            <p><strong>Branch:</strong> ${params.BRANCH}</p>
                            <p><strong>Duration:</strong> ${currentBuild.durationString}</p>
                            <hr>
                            <p>Please check the console output for details:</p>
                            <p><a href="${BUILD_URL}console">View Console Output</a></p>
                        </body>
                        </html>
                    """,
                    to: "${EMAIL_RECIPIENTS}",
                    mimeType: 'text/html'
                )
            }
        }
        
        unstable {
            script {
                echo "⚠ Build is unstable (tests may have failed)"
                
                emailext(
                    subject: "⚠ UNSTABLE: ${JOB_NAME} - Build #${BUILD_NUMBER}",
                    body: """
                        <html>
                        <body>
                            <h2 style="color: orange;">Build Unstable ⚠</h2>
                            <p><strong>Job:</strong> ${JOB_NAME}</p>
                            <p><strong>Build Number:</strong> ${BUILD_NUMBER}</p>
                            <p><strong>Branch:</strong> ${params.BRANCH}</p>
                            <p>Some tests may have failed. Please review the test reports.</p>
                            <p><a href="${BUILD_URL}testReport/">View Test Report</a></p>
                        </body>
                        </html>
                    """,
                    to: "${EMAIL_RECIPIENTS}",
                    mimeType: 'text/html'
                )
            }
        }
    }
}
