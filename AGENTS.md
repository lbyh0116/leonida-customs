# Project workflow

- Keep local game files, decoded assets, screenshots, caches, binaries and machine-specific configuration out of Git.
- Keep builds, dependency caches and generated previews under the project workspace on E: on this machine.
- For each completed project change, run the relevant checks, create a descriptive Git commit, push it to the repository's GitHub remote, and confirm that the remote revision matches. If verification or a push fails, report the specific failure.
- Close the application windows and worker processes opened for each test after the test finishes.
