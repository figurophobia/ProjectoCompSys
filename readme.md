Cosas que tiene que poder hacer la interfaz:

Debe poder escogerse entre, ejecutar en una maquina especifica, varias o todas.
Debe poder enviar la ejecucion de cualquier programa de la maquina remota (Como otros scripts, comandos de shell o de powershell)
Algunos de los scripts basicos que nos dejará escoger como opciones propias serán que tendrá serán reboot, shutdown, download and install updates.
Otras opciones basicas como scripts para ver current status, cpu y memory usage, available disk space, display de recent logs tambien.

Tiene que haber una opcion para ver los logs del systema de las operaciones remotas, y que lo almacene en un directorio /logs con un log por host


Para conectarse por ssh como root:

On the vm:
sudo nano /etc/ssh/sshd_config
-> PermitRootLogin yes
sudo systemctl restart sshd
sudo passwd root

On the host:
ssh-keygen -t rsa -b 4096 -C "figurophobia@control"
ssh-copy-id root@192.168.56.20
ssh root@192.168.56.20


