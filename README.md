# slurm-debian

First clone:
 * `git submodule update --init --recursive`

To update the submodules:
  * `git submodule foreach --recursive git pull`

Build the debian package
 * cd slurm
 * git checkout slurm-17.11
 * ln -s ../debian .
 * dch -n (maybe w must upgrade the version number)
 * debian/rules build
 * fakeroot debian/rules binary
