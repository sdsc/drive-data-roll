#!/bin/bash

# This runs a worker which will output the data to storage. To run on sentinel

celery -A seagate worker --loglevel=info