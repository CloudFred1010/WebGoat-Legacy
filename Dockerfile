FROM openjdk:8-jdk-alpine

# Create non-root user
RUN adduser -D -u 1001 webgoatuser

# Set working directory
WORKDIR /opt/webgoat

# Copy WebGoat executable JAR
COPY WebGoat-6.0.1-war-exec.jar .

# Give user permission on working dir
RUN chown -R webgoatuser:webgoatuser /opt/webgoat

# Switch to non-root user
USER webgoatuser

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "WebGoat-6.0.1-war-exec.jar"]

