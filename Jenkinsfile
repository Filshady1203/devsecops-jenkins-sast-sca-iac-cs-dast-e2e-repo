pipeline {
  agent any
  tools {
    maven 'Maven_3_8_7'
  }

  stages {
    stage('CompileandRunSonarAnalysis') {
      steps {
        withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
          sh("mvn -Dmaven.test.failure.ignore verify sonar:sonar -Dsonar.login=$SONAR_TOKEN -Dsonar.projectKey=easybuggy -Dsonar.host.url=http://localhost:9000/")
        }
      }
    }
    stage('Build') {
      steps {
        withDockerRegistry([credentialsId: "dockerlogin", url: ""]) {
          script {
            app = docker.build("filshady0016/testeb")
          }
        }
      }
    }
    stage('RunContainerScan') {
      steps {
        withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
          script {
            try {
              sh("/opt/homebrew/bin/snyk  container test filshady0016/testeb")
            } catch (err) {
              echo err.getMessage()
            }
          }
        }
      }
    }
    stage('RunSnykSCA') {
      steps {
        withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
          sh("mvn snyk:test -fn")
        }
      }
    }
    stage('RunDASTUsingZAP') {
      steps {
        sh("/Applications/ZAP.app/Contents/Java/zap.sh -port 9393 -cmd -quickurl https://www.example.com -quickprogress -quickout /Applications/ZAP.app/Contents/Java/Output.html")
      }
    }

    stage('checkov') {
      steps {
        sh("checkov -s -f main.tf")
      }
    }

  }
}
