# docker-cbioportal
A minimal standalone Docker container running the cBioPortal for Cancer Genomics (http://www.cbioportal.org/). Based on Centos. 

A pre-built Docker image is available on DockerHub: https://hub.docker.com/r/bollig/cbioportal/ . To use it, jump straight to the Run section (below). 

## Summary
The image is based on centos:6 so you should have a much easier time deploying a complete VM if this ever goes to production. For testing, I'd suggest running the container on top of a vanilla VM and avoid all the additional headache.

## Warranty
None. Don't expect any support, because I don't expect to provide any. No copyright, license, warranty, or support.

## Build
Build the container image with:

    git clone https://github.com/bollig/docker-cbioportal.git
    cd docker-cbioportal && docker build --rm -t bollig/cbioportal .
  GO GET LUNCH, THIS TAKES A WHILE

## Run
Run the container with:

    docker run --rm -p 8080:8080 --name cbioportal -it bollig/cbioportal

## Test
Test by pointing a browser to: http://localhost:8080/cbioportal

## Additional Notes
I figure you might want to try this on your own machine. In the attached screenshot, I run docker inside a boot2docker VirtualBox VM (installed via Homebrew: "brew install docker boot2docker"). The browser points to the IP address provided by $(boot2docker ip).

![Screenshot of Local cBioPortal](https://github.com/bollig/docker-cbioportal/raw/master/screenshots/local_container.png)

To add data to the database, you can expand the Dockerfile or get a root prompt with "docker exec" and start the process to install the archive (NOTE: data installed this way will be lost when the container stops):

    docker exec -it cbioportal /bin/bash
    curl -L -O [...] && tar xvf [...]
    $PORTAL_HOME/core/src/main/scripts/cbioportalImporter.py [...]
