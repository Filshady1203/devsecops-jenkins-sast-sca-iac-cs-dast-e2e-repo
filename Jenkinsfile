pipeline {
  agent any

  tools {
    maven 'Maven_3_8_7'
  }

  stages {

    stage('Compile and Run Sonar Analysis') {
      steps {
        withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
          sh '''
            mvn -Dmaven.test.failure.ignore=true \
                verify sonar:sonar \
                -Dsonar.login=$SONAR_TOKEN \
                -Dsonar.projectKey=easybuggy \
                -Dsonar.host.url=http://localhost:9000
          '''
        }
      }
    }

    stage('Build') {
      steps {
        script {
          withDockerRegistry([credentialsId: "dockerlogin", url: ""]) {
            app = docker.build("filshady0016/testeb")
          }
        }
      }
    }

    stage('Run Container Scan') {
      steps {
        withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
          script {
            try {
              sh '''
                export SNYK_TOKEN=$SNYK_TOKEN
                snyk container test filshady0016/testeb
              '''
            } catch (err) {
              echo "Snyk scan failed: ${err.getMessage()}"
            }
          }
        }
      }
    }

    stage('Run Snyk SCA') {
      steps {
        withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
          sh '''
            export SNYK_TOKEN=$SNYK_TOKEN
            mvn snyk:test -fn
          '''
        }
      }
    }

    stage('Run DAST Using ZAP') {
      steps {
        sh '''
          /Applications/ZAP.app/Contents/MacOS/ZAP.sh \
          -port 9393 \
          -cmd \
          -quickurl https://www.example.com \
          -quickprogress \
          -quickout Output.html
        '''
      }
    }

    stage('Checkov') {
      steps {
        sh '''
          checkov -s -f main.tf
        '''
      }
    }

  }
}
