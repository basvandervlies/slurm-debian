# slurm-debian

To clone the submodules:
 * `git submodule update --init --recursive`

To update the submodules:
 * `git submodule foreach --recursive git pull`

Build the debian package:
 * `cd slurm`
 * `git checkout slurm-18.08`
 * `ln -s ../debian .`
 * `dch -n` (if you want to increase the version number)
 * `debian/rules build`
 * `fakeroot debian/rules binary`
