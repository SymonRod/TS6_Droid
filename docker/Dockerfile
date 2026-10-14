# Build environment for the Flutter app: JDK 17, Flutter, Android SDK/NDK,
# Rust (+ cargo-ndk, flutter_rust_bridge_codegen) and adb.
# Versions mirror the host toolchain the project was developed with.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USER_UID=1000
ARG USER_GID=1000
# Flutter framework commit (stable, Dart 3.13.x; the project needs Dart >= 3.12).
ARG FLUTTER_REF=6a19cca56475dbfba1478ee68d7bd0c2ef891da1
ARG CMDLINE_TOOLS_VERSION=13114758
ARG ANDROID_PLATFORM=36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_NDK=28.2.13676358
ARG FRB_VERSION=2.13.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip xz-utils zip file \
        openjdk-17-jdk-headless \
        build-essential clang cmake ninja-build pkg-config perl libssl-dev \
        libglu1-mesa python3 \
    && rm -rf /var/lib/apt/lists/*

# Non-root user matching the host UID so bind-mounted files stay yours.
RUN (userdel -r ubuntu 2>/dev/null || true) \
    && groupadd -g ${USER_GID} dev && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash dev \
    && mkdir -p /opt/android-sdk /opt/flutter && chown dev:dev /opt/android-sdk /opt/flutter

USER dev
ENV HOME=/home/dev \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-sdk/ndk/${ANDROID_NDK} \
    FLUTTER_ROOT=/opt/flutter \
    CMAKE_POLICY_VERSION_MINIMUM=3.5
ENV PATH=/opt/flutter/bin:/home/dev/.pub-cache/bin:/home/dev/.cargo/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}

# Android SDK
RUN curl -fsSL -o /tmp/cmdline-tools.zip \
        https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip \
    && mkdir -p /opt/android-sdk/cmdline-tools \
    && unzip -q /tmp/cmdline-tools.zip -d /opt/android-sdk/cmdline-tools \
    && mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;android-${ANDROID_PLATFORM}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" "ndk;${ANDROID_NDK}"

# Flutter (pinned commit)
RUN git clone https://github.com/flutter/flutter.git /opt/flutter \
    && git -C /opt/flutter checkout ${FLUTTER_REF} \
    && flutter config --no-analytics --android-sdk /opt/android-sdk \
    && flutter precache --android \
    && yes | flutter doctor --android-licenses >/dev/null || true

# Rust
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable \
        -t aarch64-linux-android -t x86_64-linux-android \
    && cargo install --locked cargo-ndk \
    && cargo install --locked flutter_rust_bridge_codegen --version ${FRB_VERSION} \
    && rm -rf /home/dev/.cargo/registry /home/dev/.cargo/git

# CMake 3.22.1 is requested by a Flutter plugin; install it now, not on every run.
RUN sdkmanager "cmake;3.22.1"

# Cache mount points must exist and be owned by dev, or named volumes come up root-owned.
RUN mkdir -p /home/dev/.gradle /home/dev/.pub-cache /home/dev/.cargo/registry /home/dev/.cargo/git \
    && printf 'org.gradle.jvmargs=-Xmx6g -XX:MaxMetaspaceSize=2g\n' > /home/dev/.gradle/gradle.properties

# The tslib checkout is mounted at /workspace/tslib so that the Gradle path
# ../../../tslib (relative to flutter/android) resolves unchanged.
WORKDIR /workspace/TS6_Droid/flutter
CMD ["bash"]
