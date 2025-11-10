// Jenkins Job DSL for Spring PetClinic Pipeline
// This script can be used with the Job DSL plugin to create the pipeline job

pipelineJob('spring-petclinic-pipeline') {
    description('Automated CI/CD Pipeline for Spring PetClinic Application')
    
    // Job properties
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('10')
                    daysToKeepStr('30')
                    artifactNumToKeepStr('5')
                }
            }
        }
        
        disableConcurrentBuilds()
        
        pipelineTriggers {
            triggers {
                // Poll SCM every 5 minutes
                scm('H/5 * * * *')
                
                // GitHub webhook trigger
                githubPush()
            }
        }
    }
    
    // Parameters
    parameters {
        stringParam('BRANCH', 'main', 'Git branch to build')
        choiceParam('DEPLOY_ENV', ['staging', 'production'], 'Deployment environment')
        booleanParam('SKIP_TESTS', false, 'Skip test execution')
        booleanParam('PUSH_TO_REGISTRY', false, 'Push Docker image to registry')
    }
    
    // Pipeline definition from SCM
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/spring-projects/spring-petclinic.git')
                        credentials('github-credentials')
                    }
                    branches('*/${BRANCH}')
                    extensions {
                        cleanBeforeCheckout()
                        cloneOptions {
                            shallow(false)
                            noTags(false)
                            timeout(10)
                        }
                    }
                }
            }
            scriptPath('Jenkinsfile')
            lightweight(true)
        }
    }
    
    // Build environment
    configure { project ->
        project / 'properties' / 'jenkins.model.BuildDiscarderProperty' {
            strategy {
                'daysToKeep'('30')
                'numToKeep'('10')
                'artifactDaysToKeep'('30')
                'artifactNumToKeep'('5')
            }
        }
    }
}