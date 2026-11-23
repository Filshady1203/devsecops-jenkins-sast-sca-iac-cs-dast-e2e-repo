// Jenkinsfile for a macOS (Darwin) agent running Docker Desktop or Colima.
// Note: /bin/bash on macOS is bash 3.2, so all scripts below avoid bash 4+ features.

def runMavenStep(String label, String commands) {
  sh(label: label, script: '''#!/bin/bash
set -euo pipefail
run_maven() {
  local log status=0
  # BSD mktemp: always pass an explicit template
  log=$(mktemp "${TMPDIR:-/tmp}/maven-log.XXXXXX")
  mvn "$@" 2>&1 | tee "$log" || status=$?
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

  options {
    timeout(time: 90, unit: 'MINUTES')
  }

  environment {
    SONAR_HOST_URL = 'http://127.0.0.1:9000'
    ZAP_IMAGE      = 'ghcr.io/zaproxy/zaproxy:stable'
    // JDK used to build the project (passed to /usr/libexec/java_home -v).
    BUILD_JDK      = '1.8'
  }

  stages {
    stage('Prepare macOS agent') {
      steps {
        script {
          def mvnHome = tool 'Maven_3_8_7'
          // Jenkins started by launchd/Homebrew gets a minimal PATH, so add the usual macOS tool locations.
          env.PATH = "${mvnHome}/bin:${env.HOME}/.docker/bin:/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:${env.PATH}:/opt/anaconda3/bin"

          env.RUN_ID    = sh(script: 'uuidgen | tr "[:upper:]" "[:lower:]"', returnStdout: true).trim()
          env.APP_IMAGE = "filshady0016/testeb:${env.RUN_ID}"

          // Docker Desktop/Colima don't always expose /var/run/docker.sock. Pin the daemon socket
          // from the active docker context so later steps still work with a temporary DOCKER_CONFIG.
          env.DOCKER_HOST = sh(script: '''docker context inspect --format '{{.Endpoints.docker.Host}}' ''',
                               returnStdout: true).trim()

          // Without JAVA_HOME, /usr/bin/java on macOS is only a stub. /usr/libexec/java_home only
          // sees JDKs under /Library/Java/JavaVirtualMachines, so also check Homebrew, SDKMAN and
          // user-level installs. Only the JDK path goes to stdout; all messages go to stderr.
          env.JAVA_HOME = sh(label: 'Locate JDK', returnStdout: true, script: '''#!/bin/bash
set -u
want="${BUILD_JDK#1.}"   # "1.8" -> "8"

is_jdk() { [ -n "$1" ] && [ -x "$1/bin/java" ] && [ -x "$1/bin/javac" ]; }

candidates=()
# 1. JAVA_HOME already set on the node (Manage Jenkins > Nodes > Environment variables)
candidates+=("${JAVA_HOME:-}")
# 2. JDKs registered with macOS: the requested version first, then any
candidates+=("$(/usr/libexec/java_home -F -v "$BUILD_JDK" 2>/dev/null || true)")
candidates+=("$(/usr/libexec/java_home 2>/dev/null || true)")
# 3. Homebrew formulae (Apple Silicon and Intel prefixes): the requested version first
for prefix in /opt/homebrew /usr/local; do
  for f in "openjdk@$want" openjdk@21 openjdk@17 openjdk@11 openjdk; do
    candidates+=("$prefix/opt/$f/libexec/openjdk.jdk/Contents/Home")
  done
done
# 4. SDKMAN, plus JDKs in the system or user JVM folders (e.g. downloaded by IntelliJ)
candidates+=("$HOME/.sdkman/candidates/java/current")
for d in /Library/Java/JavaVirtualMachines/*/Contents/Home "$HOME"/Library/Java/JavaVirtualMachines/*/Contents/Home; do
  candidates+=("$d")
done

for home in "${candidates[@]}"; do
  if is_jdk "$home"; then
    echo "Using JDK at $home" >&2
    "$home/bin/java" -version >&2 2>&1 || true
    printf '%s\\n' "$home"
    exit 0
  fi
done

cat >&2 <<'MSG'
No JDK found on this Mac agent. Install one, then rerun the build:
  brew install --cask temurin@8     # JDK 8 (Intel and Apple Silicon)
  brew install openjdk@17           # or a newer JDK; then set BUILD_JDK = '17'
Or set JAVA_HOME for this node in Manage Jenkins > Nodes > <node> > Environment variables.
MSG
exit 1
''').trim()
          env.PATH = "${env.JAVA_HOME}/bin:${env.PATH}"
        }
        sh '''
          test "$(uname -s)" = Darwin
          echo "DOCKER_HOST=$DOCKER_HOST"
          echo "JAVA_HOME=$JAVA_HOME"
          java -version
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
      post {
        always {
          junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
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

            # "|| http_status=000" stops set -e from exiting silently when the server is unreachable.
            http_status=$(printf '%s' "Authorization: Bearer $SONAR_TOKEN" \
              | curl -q --silent --show-error --max-time 15 --header @- --output /dev/null \
                     --write-out '%{http_code}' "$SONAR_HOST_URL/api/v2/analysis/version") || http_status=000
            echo "SonarQube authenticated version check: HTTP $http_status"
            case "$http_status" in
              200) ;;
              000) echo "Could not reach SonarQube at $SONAR_HOST_URL. Is the server running on this Mac?"; exit 1 ;;
              401) echo 'SonarQube rejected the credential supplied by this Jenkins job. Update SONAR_TOKEN in the credential store visible to this job.'; exit 1 ;;
              403) echo 'SonarQube denied access. Check the token scope and Execute Analysis permission for easybuggy.'; exit 1 ;;
              *)   echo 'Unexpected SonarQube response. Check the configured server URL.'; exit 1 ;;
            esac

            # Run the scanner on JDK 21 (or 17) when one is installed; otherwise let it provision a JRE.
            scan_jdk=""
            for v in 21 17; do
              if candidate=$(/usr/libexec/java_home -F -v "$v" 2>/dev/null); then
                scan_jdk="$candidate"
                break
              fi
            done
            if [ -z "$scan_jdk" ] && command -v brew >/dev/null 2>&1; then
              candidate="$(brew --prefix)/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
              if [ -x "$candidate/bin/java" ]; then
                scan_jdk="$candidate"
              fi
            fi

            skip_provisioning=false
            if [ -n "$scan_jdk" ]; then
              export JAVA_HOME="$scan_jdk"
              export PATH="$JAVA_HOME/bin:$PATH"
              skip_provisioning=true
            else
              echo 'No local JDK 17/21 found; the scanner will provision its own JRE.'
            fi
            mvn -version
            run_maven -B -e org.sonarsource.scanner.maven:sonar-maven-plugin:5.5.0.6356:sonar \
              -Dsonar.projectKey=easybuggy \
              -Dsonar.host.url="$SONAR_HOST_URL" \
              -Dsonar.scanner.skipJreProvisioning="$skip_provisioning"
            ''')
          }
        }
      }
    }

    stage('Build image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerlogin',
                                          usernameVariable: 'DOCKER_USER',
                                          passwordVariable: 'DOCKER_PASS')]) {
          sh '''#!/bin/bash
            set -euo pipefail
            # Docker Desktop saves logins to the macOS Keychain ("credsStore": "desktop"/"osxkeychain").
            # A Jenkins service can't unlock it ("User interaction is not allowed"), which breaks
            # withDockerRegistry. Use a temporary config with no credsStore, removed at exit.
            DOCKER_CONFIG="$(mktemp -d "${TMPDIR:-/tmp}/docker-config.XXXXXX")"
            export DOCKER_CONFIG
            trap 'docker logout >/dev/null 2>&1 || true; rm -rf "$DOCKER_CONFIG"' EXIT
            # Keep buildx and the other CLI plugins available under the temporary config.
            printf '%s\\n' '{"cliPluginsExtraDirs":["/Applications/Docker.app/Contents/Resources/cli-plugins","/opt/homebrew/lib/docker/cli-plugins","/usr/local/lib/docker/cli-plugins"]}' \
              > "$DOCKER_CONFIG/config.json"

            printf '%s' "$DOCKER_PASS" | docker login --username "$DOCKER_USER" --password-stdin
            docker build -t "$APP_IMAGE" .
          '''
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
          rm -rf zap-reports
          mkdir -p zap-reports
          # ZAP runs as a non-root user in the container and must be able to write the report.
          chmod 0777 zap-reports
          docker pull "$ZAP_IMAGE"
          docker network create --internal "$net"
          docker run -d --name "$net-app" --network "$net" --network-alias easybuggy "$APP_IMAGE"
          docker run --rm --network "$net" --entrypoint sh "$ZAP_IMAGE" -c '
            for i in $(seq 1 60); do
              if curl -fsS --max-time 3 http://easybuggy:8080/ >/dev/null 2>&1; then exit 0; fi
              sleep 2
            done
            exit 1
          ' || { echo "EasyBuggy did not become ready."; docker logs --tail 80 "$net-app"; exit 1; }
        '''
        script {
          // The workspace must be under a Docker Desktop shared path (/Users, /Volumes, /private, /tmp).
          int status = sh(returnStatus: true, script: '''
            docker run --rm --network "easybuggy-$RUN_ID" \
              -v "$WORKSPACE/zap-reports:/zap/wrk:rw" \
              "$ZAP_IMAGE" zap-baseline.py -t http://easybuggy:8080/ -r Output.html
          ''')
          if (status == 1 || status == 2) {
            unstable("ZAP reported findings (exit ${status}).")
          } else if (status != 0) {
            error("ZAP scan failed (exit ${status}).")
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'zap-reports/Output.html', allowEmptyArchive: true
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

  post {
    always {
      // Remove the per-run image so the Mac's disk doesn't fill up.
      sh(label: 'Remove run image', script: '''#!/bin/bash
        if [ -n "${APP_IMAGE:-}" ]; then
          docker image rm -f "$APP_IMAGE" >/dev/null 2>&1 || true
          echo "Removed local image $APP_IMAGE"
        fi
      ''')
    }
  }
}
