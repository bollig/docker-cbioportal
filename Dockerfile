# cBioPortal (Standalone)
# 
# VERSION       0.1
#
#
# No copyright, license, warranty, or support.
#
# Build: 
#  docker build --rm -t cbioportal .
#
# Run: 
#  docker run --rm -p 8080:8080 -it cbioportal 
#       (load http://localhost:8080 with your favorite web browser) 

FROM centos:6

MAINTAINER Evan F. Bollig, boll0107@umn.edu

WORKDIR /root

#### BASE OS ####
RUN yum update -y
RUN yum install -y epel-release

RUN yum install -y git
RUN yum install -y unzip
RUN yum install -y ant
RUN yum install -y mysql-devel mysql-lib 
RUN yum install -y mysql-server
RUN yum install -y tar
RUN yum install -y bzip2

RUN yum install -y cmake
# NOTE: cbioportal requires jdk 1.7+, tomcat depends >= 1.6+, and maven depends <= 1.7
RUN yum install -y java-1.7.0-openjdk-devel

# Install Tomcat
# NOTE: tomcat could be installed by RPM, but its less clear what changes to make compared to a vanilla bin
RUN curl -L -O http://apache.mirrors.tds.net/tomcat/tomcat-7/v7.0.67/bin/apache-tomcat-7.0.67.tar.gz
RUN cd /usr/local && tar xfz /root/apache-tomcat-7.0.67.tar.gz 
RUN ln -s /usr/local/apache-tomcat-7.0.67 /usr/local/tomcat
# This wrapper is not useful outside of a supervisord env
ADD supervisord_wrapper.sh /usr/local/tomcat/bin/supervisord_wrapper.sh
RUN chmod +x /usr/local/tomcat/bin/supervisord_wrapper.sh

# REQUIRED: Register the jdbc connector for cbioportal 
ADD tomcat_context.xml /usr/local/tomcat/conf/context.xml

# Install Maven
RUN curl -L -O http://supergsego.com/apache/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
RUN cd /usr/local && tar xzf /root/apache-maven-3.3.9-bin.tar.gz
RUN ln -s /usr/local/apache-maven-3.3.9 /usr/local/maven

#### SOFTWARE DEPENDENCIES ####

RUN git clone https://github.com/cBioPortal/cbioportal.git

# NOTE: not sure if any of this data is actually necessary, but I'm pre-loading it into mysql
RUN curl -L -O http://cbio.mskcc.org/cancergenomics/public-portal/downloads/cbioportal-seed.sql.gz

## FROM https://github.com/cBioPortal/cbioportal/wiki/Pre-Build-Steps

WORKDIR /root/cbioportal

#NOTE: the default logging is sufficient. 
#log4j writes to java.io.tmpdir (/tmp) override with java -Djava.io.tmpdir=
RUN cd src/main/resources \
    && cp portal.properties.EXAMPLE portal.properties \
    && cp log4j.properties.EXAMPLE log4j.properties

# Populate MySQL 
RUN mysql_install_db 
RUN ( cd /usr ; /usr/bin/mysqld_safe & ) \
    && sleep 10 \
    && ( \
        mysql -u root -e "CREATE DATABASE cbioportal; \
                          CREATE DATABASE cgds_test; \
                          CREATE USER 'cbio_user'@'localhost' IDENTIFIED BY 'somepassword'; \
                          GRANT ALL ON cbioportal.* TO 'cbio_user'@'localhost'; \
                          GRANT ALL ON cgds_test.* TO 'cbio_user'@'localhost'; \
                          flush privileges; "; \
        echo "Loading base cBioPortal Database"; \
        # This takes a LONG time and requires ~10GB of space to build the container: 
        gunzip -c /root/cbioportal-seed.sql.gz | mysql --user cbio_user --password=somepassword cbioportal; \
    ) \
    && tail /var/log/mysqld.log \
    && mysqladmin shutdown

# Setup cbioportal compilation
RUN mkdir -p /root/.m2
ENV JAVA_HOME /usr/lib/jvm/java
ADD maven_settings.xml  /root/.m2/settings.xml

ENV PORTAL_HOME /root/cbioportal

WORKDIR /root/cbioportal

### Install cbioportal ###

# NOTE: cbioportal requires java >=1.7.0, maven requires <=1.7.0
RUN /usr/local/maven/bin/mvn -DskipTests clean install
# This will self-install on next Tomcat start
RUN cp $PORTAL_HOME/portal/target/cbioportal.war /usr/local/tomcat/webapps/cbioportal.war
# This is the JDBC driver needed by cbioportal (downloaded during clean install)
RUN cp ~/.m2/repository/mysql/mysql-connector-java/5.1.16/mysql-connector-java-5.1.16.jar /usr/local/tomcat/lib/.

### Load the sample study ###

RUN curl -L -O http://cbio.mskcc.org/cancergenomics/public-portal/downloads/brca-example-study.tar.gz
RUN tar xfz brca-example-study.tar.gz
ENV CONNECTOR_JAR /usr/local/tomcat/lib/mysql-connector-java-5.1.16.jar
ENV CORE_JAR $PORTAL_HOME/core/target/core-1.0.3.jar

# I kept getting an error: "zero length field name in format" when loading
# meta-data. This is due to Python 2.6.6. Upgrade to python 2.7 or 3.1+ and it
# will work 
RUN curl -L -O https://repo.continuum.io/miniconda/Miniconda-latest-Linux-x86_64.sh
RUN sh Miniconda-latest-Linux-x86_64.sh -b -p /usr/local/miniconda
ENV PATH /usr/local/miniconda/bin:$PATH

# Load the brca example data (must start the mysql server for each RUN): 
# RUN is a separate layer of container, so consider it a fresh boot of a VM. No services run by default. 
RUN ( cd /usr ; /usr/bin/mysqld_safe & ) \
    && sleep 10 \
    && ( \
        # Load meta-data for the study: 
        $PORTAL_HOME/core/src/main/scripts/cbioportalImporter.py --jvm-args "-Dspring.profiles.active=dbcp -cp $CONNECTOR_JAR:$CORE_JAR" --command import-study --meta-filename portal-study/meta_study.txt \
        && \
        # Then, load copy number, mutation data and expression data:
        $PORTAL_HOME/core/src/main/scripts/cbioportalImporter.py --jvm-args "-Dspring.profiles.active=dbcp -cp $CONNECTOR_JAR:$CORE_JAR" --command import-study-data --meta-filename portal-study/meta_CNA.txt --data-filename portal-study/data_CNA.txt \
        && \
        $PORTAL_HOME/core/src/main/scripts/cbioportalImporter.py --jvm-args "-Dspring.profiles.active=dbcp -cp $CONNECTOR_JAR:$CORE_JAR" --command import-study-data --meta-filename portal-study/meta_mutations_extended.txt --data-filename portal-study/data_mutations_extended.txt \
        && \
        $PORTAL_HOME/core/src/main/scripts/cbioportalImporter.py --jvm-args "-Dspring.profiles.active=dbcp -cp $CONNECTOR_JAR:$CORE_JAR" --command import-study-data --meta-filename portal-study/meta_expression_median.txt --data-filename portal-study/data_expression_median.txt \
        && \
        # Lastly, load the case sets and clinical attributes:
        $PORTAL_HOME/core/src/main/scripts/cbioportalImporter.py --jvm-args "-Dspring.profiles.active=dbcp -cp $CONNECTOR_JAR:$CORE_JAR" --command import-case-list --meta-filename portal-study/case_lists \
        && \
        $PORTAL_HOME/core/src/main/scripts/cbioportalImporter.py --jvm-args "-Dspring.profiles.active=dbcp -cp $CONNECTOR_JAR:$CORE_JAR" --command import-study-data --meta-filename portal-study/meta_clinical.txt --data-filename portal-study/data_clinical.txt \
    ) \
    && mysqladmin shutdown

# TODO: is this needed?  
#RUN curl -L -O http://cbio.mskcc.org/cancergenomics/public-portal/downloads/MAF_example.txt

#### DOCKER SPECIFIC SETUP ######
# There will be no need for this stuff when building a production VM. 

# Dummy entrypoint does not add pro- or epi-log tasks 
ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

# Use iptables to expose 8080 to the world (for Tomcat)
EXPOSE 8080 

# supervisord is used to demo multiple services in one container
# You would want to use systemctl enable mysqld, systemctl enable tomcat
RUN yum install -y supervisor
ADD supervisord.conf /etc/supervisord.conf
RUN mkdir -p /var/log/supervisor
RUN chmod -R 777 /var/log/supervisor
CMD ["/usr/bin/supervisord"]
