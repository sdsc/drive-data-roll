from celery import Celery
import filelock
import os

data_dir = "data"
if not os.path.exists(data_dir):
    os.makedirs(data_dir)

with open('/opt/rocks/etc/rabbitmq.conf','r') as f:
    rabbitmq_server = f.read().rstrip()

with open('/opt/rocks/etc/rabbitmq_seagate.conf','r') as f:
    rabbitmq_password = f.read().rstrip()


app = Celery('seagate', broker='amqp://seagate:%s@%s/seagate'%(rabbitmq_password, rabbitmq_server))

@app.task
def send_data(jobid, data):
    file_path = "data/%s"%jobid
    lock = filelock.FileLock("%s.lock"%file_path)
    with lock:
        with open(file_path, "a") as f:
            f.write(data)
            f.write("\n")

