# drive-data package README

This directoy contains the build files for the drive-data package, which is part
of the drive-data roll. Unique to the drive-data roll/package is the bundled 
capability to download & size/checksum verify binaries that are used to build
the package/roll from a controlled server.

To allow this process to complete you simply need to add the size, git hash 
and binary filename to a file in this directory. The default name for that
file is `binary_hashes` but it can be changed in `pull.mk` if you wish. To 
generate the proper content execute the following command(s) or script their
equivalent...

	BINARY_FILE=<name_of_your_file>
	echo `ls -l ${BINARY_FILE} | awk '{print $5}'` \
	     "  " \
	     `git hash-object -t blob ${BINARY_FILE}` \
	     "  " \
	     `basename ${BINARY_FILE}` > binary_hashes

Then upload your `${BINARY_FILE}` to the server listed in the `pull.mk` file
into the web accessible directory...

	$(DL.SERVER)/$(DL.PATH)

