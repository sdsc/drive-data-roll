#!/opt/python/bin/python

# This sends data
# Not sure if we want to read from file or pass as argument or do something else

from seagate import send_data

send_data.delay(jobid=100, data="dadadadadata")
