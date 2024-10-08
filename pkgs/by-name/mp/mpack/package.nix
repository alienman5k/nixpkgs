{
  lib,
  stdenv,
  fetchurl,
  testers,
  mpack,
}:

stdenv.mkDerivation rec {
  pname = "mpack";
  version = "1.6";

  src = fetchurl {
    url = "http://ftp.andrew.cmu.edu/pub/mpack/mpack-${version}.tar.gz";
    hash = "sha256-J0EIuzo5mCpO/BT7OmUpjmbI5xNnw9q/STOBYtIHqUw=";
  };

  patches = [
    ./build-fix.patch
    ./sendmail-via-execvp.diff
    ./CVE-2011-4919.patch
  ];

  postPatch = ''
    for f in *.{c,man,pl,unix} ; do
      substituteInPlace $f --replace /usr/tmp /tmp
    done

    # this just shuts up some warnings
    for f in {decode,encode,part,unixos,unixpk,unixunpk,xmalloc}.c ; do
      sed -i 'i#include <stdlib.h>' $f
    done
  '';

  postInstall = ''
    install -Dm644 -t $out/share/doc/mpack INSTALL README.*
  '';

  enableParallelBuilding = true;

  passthru.tests = {
    version = testers.testVersion {
      command = ''
        mpack 2>&1 || echo "mpack exited with error code $?"
      '';
      package = mpack;
      version = "mpack version ${version}";
    };
  };

  meta = with lib; {
    description = "Utilities for encoding and decoding binary files in MIME";
    license = licenses.free;
    platforms = platforms.linux;
    maintainers = with maintainers; [ tomodachi94 ];
  };
}
