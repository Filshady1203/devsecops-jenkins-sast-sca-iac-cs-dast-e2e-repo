def scanWithSnyk(String command) {
  withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
    int status = sh(script: command, returnStatus: true)
    if (status == 1) {
      unstable('Snyk reported findings. See the stage log.')
    } else if (status != 0) {
      error("Snyk scan failed (exit ${status}).")
    }
  }
}

pipeline {
  agent any
  tools { maven 'Maven_3_8_7' }

  environment {
    SONAR_HOST_URL = 'http://127.0.0.1:9000'
    ZAP_IMAGE = 'ghcr.io/zaproxy/zaproxy:stable'
  }

  stages {
    stage('Prepare macOS agent') {
      steps {
        script {
          def mvnHome = tool 'Maven_3_8_7'
          env.PATH = "${mvnHome}/bin:${env.HOME}/.docker/bin:/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:${env.PATH}"
          env.PATH = "${env.PATH}:/opt/anaconda3/bin"
          env.RUN_ID = sh(script: 'uuidgen | tr A-Z a-z', returnStdout: true).trim()
          env.APP_IMAGE = "filshady0016/testeb:${env.RUN_ID}"
        }
        sh '''
          test "$(uname -s)" = Darwin
          mvn --version
          docker version
          snyk --version
          checkov --version
        '''
      }
    }

    stage('Compile and run Sonar analysis') {
      steps {
        withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
          sh 'mvn -B -Dmaven.test.failure.ignore=true verify sonar:sonar -Dsonar.projectKey=easybuggy'
        }
      }
    }

    stage('Build') {
      steps {
        withDockerRegistry([credentialsId: 'dockerlogin', url: '']) {
          sh 'docker build -t "$APP_IMAGE" .'
        }
      }
    }

    stage('Run container scan') {
      steps {
        script { scanWithSnyk('snyk container test "$APP_IMAGE" --file=Dockerfile') }
      }
    }

    stage('Run Snyk SCA') {
      steps {
        script { scanWithSnyk('snyk test --file=pom.xml') }
      }
    }

    stage('Run ZAP baseline') {
      steps {
        sh '''
          set -eu
          net="easybuggy-$RUN_ID"
          mkdir -p zap-reports
          rm -f zap-reports/Output.html
          docker pull "$ZAP_IMAGE"
          docker network create --internal "$net"
          docker run -d --name "$net-app" --network "$net" --network-alias easybuggy "$APP_IMAGE"

          docker run --rm --network "$net" --entrypoint sh "$ZAP_IMAGE" -c '
            for i in $(seq 1 60); do
              if curl -fsS --max-time 3 http://easybuggy:8080/ >/dev/null 2>&1; then
                exit 0
              fi
              sleep 2
            done
            exit 1
          ' || { docker logs --tail 80 "$net-app"; exit 1; }
        '''
        script {
          int status = sh(returnStatus: true, script: '''
            docker run --rm --network "easybuggy-$RUN_ID" -v "$WORKSPACE/zap-reports:/zap/wrk:rw" "$ZAP_IMAGE" zap-baseline.py -t http://easybuggy:8080/ -r Output.html
          ''')
          if (status == 1 || status == 2) {
            unstable("ZAP reported findings (exit ${status}).")
          } else if (status != 0) {
            error("ZAP scan failed (exit ${status}).")
          }
        }
        archiveArtifacts artifacts: 'zap-reports/Output.html'
      }
      post {
        always {
          sh '''
            docker rm -f "easybuggy-$RUN_ID-app" >/dev/null 2>&1 || true
            docker network rm "easybuggy-$RUN_ID" >/dev/null 2>&1 || true
          '''
        }
      }
    }

    stage('Checkov') {
      steps {
        sh 'checkov -s -f main.tf'
      }
    }
  }
}
