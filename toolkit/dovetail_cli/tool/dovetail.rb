class Dovetail < Formula
  desc "Builds, packages, signs and publishes a Flutter desktop app"
  homepage "https://github.com/mateussiqueira/dovetail"
  version "0.1.0"
  license :cannot_represent

  depends_on :macos
  depends_on arch: :arm64

  depends_on "minisign"
  depends_on "msitools"
  depends_on "osslsigncode"
  depends_on "rpm"
  depends_on "squashfs"

  url "file://#{ENV["DOVETAIL_RELEASE_DIR"] || "/tmp"}/dovetail-0.1.0-macos-arm64.tar.gz"
  sha256 "a46fa7b811da92cbf2ee40f73a14f99fcc8eaed288df76d59353f555a00cfeb3"

  def install
    bin.install "dovetail"
  end

  def caveats
    <<~EOS
      dovetail drives the tools it needs rather than reimplementing them.
      The ones this formula installs cover packaging and signing:

        minisign       signs the update manifest
        msitools       wixl, which builds a Windows MSI without Windows
        osslsigncode   Authenticode, also without Windows
        rpm            rpmbuild, for the Linux .rpm
        squashfs       mksquashfs, the filesystem an AppImage carries

      Two are not installed here, on purpose:

        flutter        dovetail build calls it; you already have it
        makensis       only if you want the NSIS installer as well as the MSI

      One cannot be installed by anyone: an AppImage is a runtime with a
      squashfs appended, and that runtime is someone else's ELF. Take
      runtime-<arch> from the AppImage/type2-runtime releases and pass its
      path to --appimage-runtime.

      Run "dovetail doctor" to see what this machine can and cannot build.
    EOS
  end

  test do
    assert_match "dovetail #{version}", shell_output("#{bin}/dovetail --version")
    assert_match "target:", shell_output("#{bin}/dovetail doctor --target macos", 2)
  end
end
