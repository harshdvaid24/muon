CI builds and tests the TypeScript tool server on macОS runners.
The SwiftUI app targets macOS 26 / Xcode 26, which GitHub-hosted runners do not
yet provide, so the app is built locally (see the root README). When a runner
image with Xcode 26 is available, add a job that runs `scripts/build.sh test`.
