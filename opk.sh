#!/bin/sh

#
#  opk.sh
#  OPK
#
#  Copyright (c) 2021-2022, Joona Holkko, Arkaitz William Goni Hedger
#

# Update this number every version
opkver="1.0.2"
# Sourcing the config file
. /etc/opk.conf

# Some escape codes for colour
RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# This will be run by the install script. 
addtodb() {
  linenum=$(grep -n "^$pkgname()" "/usr/share/opk/packages.sh" | cut -d : -f1 | tail -n 1) 2>/dev/null

  # This will run if the package has already been installed and is being updated
  if [ $linenum -ge 0 ] 2>/dev/null; then
    vernum=$((linenum + 2))
    depnum=$((linenum + 3))
    sed "$vernum s/.*/  ver=\"$pkgver\"/" /usr/share/opk/packages.sh > /tmp/packages_tmp.sh 
    mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
    sed "$depnum s/.*/  deps=\"$deps\"/" /usr/share/opk/packages.sh > /tmp/packages_tmp.sh
    mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
    
  else 
    # If the package is new this will be run
    echo "pkg_$pkgname() {" >> "/usr/share/opk/packages.sh"
    echo "  name=\"$pkgname\"" >> "/usr/share/opk/packages.sh"
    echo "  ver=\"$pkgver\"" >> "/usr/share/opk/packages.sh"
    echo "  LICENSE=\"$LICENSE\"" >> "/usr/share/opk/packages.sh"
    echo "  deps=\"$deps\"" >> "/usr/share/opk/packages.sh"
    if [ $SILENT = "true" ] 2>/dev/null; then
      echo "  explicit=\"false\"" >> "/usr/share/opk/packages.sh"
    else
      echo "  explicit=\"true\"" >> "/usr/share/opk/packages.sh"
    fi
    echo "}" >> "/usr/share/opk/packages.sh"
    echo "" >> "/usr/share/opk/packages.sh"

  fi
}

checksumfailed() {
  echo -e "${RED}The checksum has failed, This could mean the package has been tampered with or you may be installing a custom package. \nContinue at your own risk! ${NC}"
  echo "Continue? (y/N)"
  read confirm
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    :
  else
    echo "Aborting"
    exit
  fi
}

install() {
  for i in $pkgs; do 
    cd $REPO/*/$i/out/
    if [ -e *.opk ]; then
      # Check the checksum of the opk file
      sha512sum -c $pkgname-$pkgver.opk.sha512 || checksumfailed
      # Extract the archive
      tar -xf $i-*.opk 
      # Make a tempfolder and extract the opk file into it
      mkdir tmp 
      cd tmp
      tar -xf ../$pkgname-$pkgver.opk
      cd ..
      cp -r tmp/* /
      addtodb
      mv tmp/.DIRLIST /usr/share/opk/removeinfo/$pkgname-$pkgver.DIRLIST
      # Run any postinstall scripts
      [ -e .POSTINSTALL ] && sh .POSTINSTALL
      # Clean up the temp folder
      rm -rf tmp
      echo -e "${GREEN}Installation of $pkgname completed.${NC}"
    fi

  done
}

build() {
  for i in $pkgs; do
    cd $REPO/*/$i/
    # Clears source dir
    rm -rf ./src
    rm -rf ./out
    # Makes and cd's into source dir, also creates the output directory
    mkdir -p ./out/$i
    mkdir ./src
    # outdir is what will contain the final source before compression
    outdir="$PWD/out/$i"
    cd ./src
    # Sources build file
    . ../OPKBUILD

    # Remove any preinstalled packages from the dependancy list
    # These variable checks are in place as if either value is null the program will set deps and preinstalled to error messages which breaks stuff
    [ -n "$deps" ] && preinstalled=`grep '()' /usr/share/opk/packages.sh | cut -d '(' -f1 | cut -d '_' -f2`
    [ -n "$preinstalled" ] && deps=`echo $deps | sed "s/$preinstalled//g"`

    # Tell the user what dependancies need to be installed
    if [ -n "$deps" ] && [ SILENT="false" ]; then 
      echo -ne "${GREEN} The following dependancies need to be installed:${NC} \n $deps \n ${GREEN}Continue? (Y/n)${NC} "
      read confirm
      [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && exit 
      opk -Z $deps
    fi

    [ -n "$deps" ] && [ SILENT="true" ] && opk -I $deps     
    . /usr/share/opk/packages.sh 
    pkg_$pkgname 2>/dev/null

    if [ $ver = $pkgver ] 2>/dev/null; then
      echo -e "${GREEN}The package is already installed and up to date${NC}"
    else
      # Downloads stuff
      fetch
      ## Verify checksums
      sha512sum -c $pkgname-$pkgver.tar.xz.sha512 || checksumfailed
      ## Make output dir
      build
      package
      mkdir -p $outdir/usr/share/licenses/
      for license in $LICENSE
      do 
        cat $license >> $outdir/usr/share/licenses/$pkgname.license
      done

      ## Compressing the package into a .opk file 
      cd $outdir
      find ./ > .DIRLIST 
      echo "pkgname=$pkgname" >> .OPKINFO
      echo "pkgver=$pkgver" >> .OPKINFO
      echo "deps=$deps" >> .OPKINFO
      echo "LICENSE=$LICENSE" >> .OPKINFO


      [ -e "../../POSTINSTALL" ] 2>/dev/null && cp "../../POSTINSTALL" ".POSTINSTALL" 
      tar -cf "../$pkgname-$pkgver.tar" ./* .* 2>/dev/null

      xz -5 "../$pkgname-$pkgver.tar" 
      mv "../$pkgname-$pkgver.tar.xz" "../$pkgname-$pkgver.opk"
      # Generate sha512sum for the opk file

      cd ../
      sha512sum "./$pkgname-$pkgver.opk" > "./$pkgname-$pkgver.opk.sha512"
      rm -rf $outdir
      rm -rf ../src
    
      echo -e "${GREEN}The build of $pkgname completed sucessfully.${NC}"
    fi
  done
}

remove() {
  for i in $pkgs; do 
    # Source the packag info
    . /usr/share/opk/packages.sh
    # Check if $i is installed
    if pkg_$i 2>/dev/null; then 
      # Source the proper package info
      pkg_$i

      for e in $deps; do
        . /usr/share/opk/packages.sh
        pkg_$e
        if [ $explicit = "false" ]; then
          opk -R $name
        fi
      done
      while read -r path
      do
        cd /
        # We disable error messages because it will not remove directories which is intended
        # but will look like an error to a user
        rm "$path" 2>/dev/null
      done < /usr/share/opk/removeinfo/$name-$ver.DIRLIST && echo -e "${GREEN}The package $name has been uninstalled.${NC}"
      linenum=$(grep -n "^pkg_$name()" "/usr/share/opk/packages.sh" | cut -d : -f1 | tail -n 1)

      # Remove package from the package database
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
      sed "$linenum d" "/usr/share/opk/packages.sh" > /tmp/packages_tmp.sh
      mv /tmp/packages_tmp.sh /usr/share/opk/packages.sh
    else
      echo -e "${RED} The package does not exist."
    fi
  done
}

update_repos() {
  cd /tmp 
  curl -L $MIRROR/REPO.tar.xz -o REPO.tar.xz  
  curl -L $MIRROR/REPO.tar.xz.sha512 -o REPO.tar.xz.sha512
  sha512sum -c REPO.tar.xz.sha512 || checksumfailed
  tar -xf REPO.tar.xz
  cp -r ./repo/* $REPO/
  rm -rf ./repo
}

update_packages() {
  . /usr/share/opk/packages.sh
  a=`grep "^pkg_" /usr/share/opk/packages.sh | cut -d '(' -f1`
  for i in $a; do 
    . /usr/share/opk/packages.sh
    # Gets the version of the installed package.
    $i 
    currentver=$ver
    # Gets the version of the package in the repo.
    . $REPO/*/$name/OPKBUILD
    newver=$ver
    # Compares the package numbers.
    if [ "$(printf '%s\n' "$currentver" "$newver" | sort -V | head -n1)" = "$newver" ]; then
      echo "Greater than or equal to ${newver}"
    else
      echo "Less than ${newver}"
    fi
}

help() {
echo -e "${ORANGE}Orange${NC} Package Keeper:
${ORANGE}
            ^!?JJ?!^
           ^?YYYYYYJ~
           ~?YYYYYY?!.
          .!?YYYYYY7!.
        .. ^7JJJJJJ!^...
        .^::^~~!!!~:.^^.
          .:^~~~~~~^:.
${NC}

        opk install <package>  || opk -I <package>
        Installs the chosen package.

        opk remove <package>   || opk -R <package>
        Removes the chosen package, this is not currently implemented.

        opk build <package> || opk -B <package> 
        Builds the selected package but does not install it.
        
        opk silent <package> || opk -Z <package>
        Installs the package without asking questions.

        opk list || opk -l 
        Lists all installed packages,
        if provided with an argument it will search the installed packages.

        opk search || opk -S 
        Searches for the selected package in the repositories

        opk help || opk -H 
        Shows this message

        opk version || opk -V 
        Shows the opk version

        For more in depth info please check the manpage (man opk)"

}

ver() {
  echo -e "${ORANGE}Orange Package Keeper: Version: $opkver

    ^!?JJ?!^    
   ^?YYYYYYJ~   
   ~?YYYYYY?!.  
  .!?YYYYYY7!.  
.. ^7JJJJJJ!^...
.^::^~~!!!~:.^^.
  .:^~~~~~~^:.  
${NC}
  "
}

# This will first build the program and then run the install function
[ "${1}" = '-I' ] || [ "${1}" = 'install' ] && shift 1 && pkgs=$@ && build && install && exit

# This will build the program and not run the install function afterwards 
[ "${1}" = '-B' ] || [ "${1}" = 'build' ] && shift 1 && pkgs=$@ && build && exit

# This will source the package dir and using a for loop check the pkgversions of /usr/share/opk/packages.sh with those in the repos.
[ "${1}" = '-U' ] || [ "${1}" = 'update' ] && shift 1 && pkgs=$@ && echo "Function not yet implemented" && exit

# This will just run the remove function for the selected packages, use a similar shift 1 && pkgs=$@ thing as seen previously
[ "${1}" = '-R' ] || [ "${1}" = 'remove' ] && shift 1 && pkgs=$@ && remove && exit

# This will be used to install dependancies, it will run a modified version of the build function without questions (well i havnt added in any questions atm but that is a TODO)
[ "${1}" = '-Z' ] || [ "${1}" = 'silent' ] && shift 1 && pkgs=$@ && SILENT="true" && build && install && exit

# List installed, recursively source items in the packages.sh and print the package names (maybe add a description for the packages TODO) (i also want this to have a search feature)
[ "${1}" = '-L' ] || [ "${1}" = 'list' ] && echo "Function not yet implemented" && exit

# Search function, not really sure how i plan to do this one but probably using ls and grep
[ "${1}" = '-S' ] || [ "${1}" = 'search' ] && echo "Function not yet implemented" && exit

# Prints the help message
[ "${1}" = '-H' ] || [ "${1}" = 'help' ] && help && exit

# Prints the current opk version, maybe we could add some more info here?? idk
[ "${1}" = '-V' ] || [ "${1}" = 'version' ] && ver && exit

# This will run if no arguments where recognised (which is why all the exits are important)
echo -e "${ORANGE}Orange${NC} Package Keeper:
${RED}Invalid command${NC}

Run opk -H to see the available commands"

