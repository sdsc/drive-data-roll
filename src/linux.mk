SRCDIRS = `find * -prune\
	  -type d 	\
	  ! -name CVS	\
          ! -name send-data \
          ! -name drive-data-slurm \
	  ! -name .`
