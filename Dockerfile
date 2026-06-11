# ---------- BUILD STAGE ----------
FROM maven:3.8.8-eclipse-temurin-8 AS builder

WORKDIR /usr/src/easybuggy

COPY . .

RUN mvn -B clean package -DskipTests

# ---------- RUNTIME STAGE ----------
FROM eclipse-temurin:8-jre

WORKDIR /app

# create logs directory (important)
RUN mkdir -p /app/logs

# copy built jar (handles versioned jar safely)
COPY --from=builder /usr/src/easybuggy/target/*.jar /app/easybuggy.jar

EXPOSE 9009 7900

CMD ["java", \
  "-XX:MaxMetaspaceSize=128m", \
  "-Xmx256m", \
  "-XX:MaxDirectMemorySize=90m", \
  "-XX:+UseSerialGC", \
  "-XX:+HeapDumpOnOutOfMemoryError", \
  "-XX:HeapDumpPath=/app/logs", \
  "-XX:ErrorFile=/app/logs/hs_err_pid%p.log", \
  "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:9009", \
  "-Dderby.stream.error.file=/app/logs/derby.log", \
  "-Dderby.infolog.append=true", \
  "-Dderby.language.logStatementText=true", \
  "-Dderby.locks.deadlockTrace=true", \
  "-Dderby.locks.monitor=true", \
  "-Dderby.storage.rowLocking=true", \
  "-Dcom.sun.management.jmxremote", \
  "-Dcom.sun.management.jmxremote.port=7900", \
  "-Dcom.sun.management.jmxremote.ssl=false", \
  "-Dcom.sun.management.jmxremote.authenticate=false", \
  "-ea", \
  "-jar", \
  "easybuggy.jar" \
]
