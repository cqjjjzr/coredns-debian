# Debian package for CoreDNS

Install the build dependencies on Debian:

```sh
sudo apt install build-essential debhelper golang-any git ca-certificates
```

Build from a local source directory, a release tag, or the latest stable tag:

```sh
./build.sh --source ../coredns
./build.sh --tag TAG
./build.sh
```

Use `--repo URL` to select another Git repository and `--output DIR` to change
the output directory from `./build`. Builds use a temporary source copy and
produce native-architecture `.deb`, `.buildinfo`, and `.changes` files.

The Go version comes from the selected CoreDNS source. The package changelog
uses its release summary and noteworthy changes from `notes/coredns-VERSION.md`,
falling back to the one-line `debian/changelog` if no release text is available.

Build in a Debian container with Podman (or replace `podman` with `docker`):

```sh
podman build -f Containerfile -t coredns-debian .
mkdir -p build
podman run --rm -v "$(pwd)/build:/out" coredns-debian
```

This builds the latest stable tag and writes the package files to `./build`.
Append `--tag TAG` to select a release. To use local sources instead:

```sh
podman run --rm -v "$(pwd)/build:/out" -v "$(realpath ../coredns):/source:ro" \
    coredns-debian --source /source
```
