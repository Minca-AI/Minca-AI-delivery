# Fixture image for the pre-build input of image.yml. generated/greeting.txt does not exist in the
# repository: pre-build.sh creates it, so a build that runs before the script fails at COPY.
FROM busybox:1.37
COPY generated/greeting.txt /greeting.txt
USER 65532:65532
ENTRYPOINT ["cat", "/greeting.txt"]
