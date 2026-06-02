# Imagen base MySQL 8 oficial
FROM mysql:8
ENV MYSQL_DATABASE=tienda_perritos
# Se ejecuta automáticamente la primera vez que se levante el contenedor
COPY init.sql /docker-entrypoint-initdb.d/
# Exponer el puerto de MySQL
EXPOSE 3306
