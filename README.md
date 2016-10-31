# alpine-glassfish (w/nginx & pagespeed)

Glassfish 4.1.1 and Nginx compiled with Google's PageSpeed all on top of Alpine Linux.

Credit to:

 * https://github.com/wunderkraut/alpine-nginx-pagespeed
 * https://github.com/glassfish/docker

Run with a command like:

```
docker run --name webserver -p 80:80 -v `pwd`/site/localhost.conf:/etc/nginx/conf.d/localhost.conf -v `pwd`/site/html:/app/html -d jethro/alpine-glassfish
```

