def runMavenStep(String label, String commands) {
  sh(label: label, script: '''#!/bin/bash
set -eu
run_maven() {
  local log status
  log=$(mktemp)
  mvn "$@" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  if [ "$status" -ne 0 ]; then
    echo "Maven failure details:"
    awk '/Failed to execute goal|Caused by:/ && ++matches <= 12 {print}' "$log"
  fi
  rm -f "$log"
  return "$status"
}
''' + commands)
}

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

  parameters {
    string(name: 'SONAR_ORGANIZATION', defaultValue: '', trim: true, description: 'Organization key from SonarQube Cloud EU')
    string(name: 'SONAR_PROJECT_KEY', defaultValue: '', trim: true, description: 'Project key from SonarQube Cloud EU')
  }

  environment {
    SONAR_HOST_URL = 'https://sonarcloud.io'
    ZAP_IMAGE = 'ghcr.io/zaproxy/zaproxy:stable'
  }

  stages {
    stage('Prepare macOS agent') {
      steps {
        script {
          def mvnHome = tool 'Maven_3_8_7'
          env.PATH = "${mvnHome}/bin:${env.HOME}/.docker/bin:/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:${env.PATH}:/opt/anaconda3/bin"
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

    stage('Maven verify') {
      steps {
        script {
          runMavenStep('Build EasyBuggy', 'run_maven -B -e -Dmaven.test.failure.ignore=true verify')
        }
      }
    }

    stage('SonarQube analysis') {
      steps {
        withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
          script {
            runMavenStep('Analyze EasyBuggy', '''
            set +x
            if [[ -z "${SONAR_TOKEN:-}" || "$SONAR_TOKEN" == *[[:space:]]* ]]; then
              echo 'Jenkins credential SONAR_TOKEN is empty or contains whitespace. Update its Secret text value.'
              exit 1
            fi
            : "${SONAR_ORGANIZATION:?Set SONAR_ORGANIZATION in Build with Parameters}"
            : "${SONAR_PROJECT_KEY:?Set SONAR_PROJECT_KEY in Build with Parameters}"
            echo "Analyzing $SONAR_ORGANIZATION/$SONAR_PROJECT_KEY on $SONAR_HOST_URL"

            scan_jdk=$(/usr/libexec/java_home -F -v 21 2>/dev/null || true)
            if [ -z "$scan_jdk" ] && command -v brew >/dev/null 2>&1; then
              scan_jdk="$(brew --prefix)/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
            fi

            skip_provisioning=false
            if [ -x "$scan_jdk/bin/java" ] && [ -n "$scan_jdk" ]; then
              export JAVA_HOME="$scan_jdk"
              export PATH="$JAVA_HOME/bin:$PATH"
              skip_provisioning=true
            fi
            mvn -version
            run_maven -B -e org.sonarsource.scanner.maven:sonar-maven-plugin:5.5.0.6356:sonar -Dsonar.host.url="$SONAR_HOST_URL" -Dsonar.organization="$SONAR_ORGANIZATION" -Dsonar.projectKey="$SONAR_PROJECT_KEY" -Dsonar.scanner.skipJreProvisioning="$skip_provisioning"
            ''')
          }
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
              if curl -fsS --max-time 3 http://easybuggy:8080/ >/dev/null 2>&1; then exit 0; fi
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
      steps { sh 'checkov -s -f main.tf' }
    }
  }
}
