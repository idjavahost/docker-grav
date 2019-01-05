#!/bin/bash
set -e

if [[ ! -f /etc/.setupdone ]]; then

    # RUN INITIAL SETUP
    RANDPASS=$(date | md5sum | awk '{print $1}')
    mkdir $HOME/grav
    addgroup -g 1001 $USERGROUP
    adduser -D -u 1001 -h $HOME -s /bin/bash -G $USERGROUP $USERNAME
    echo "${USERNAME}:${RANDPASS}" | chpasswd &> /dev/null

    echo "EDITOR=nano" > $HOME/.profile

    if [[ ! -x "$(command -v dockerize)" ]]; then
        echo "=========================================================="
        echo " INSTALL DOCKERIZE"
        echo "=========================================================="
        wget -q https://github.com/jwilder/dockerize/releases/download/v$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-v$DOCKERIZE_VERSION.tar.gz
        tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-v$DOCKERIZE_VERSION.tar.gz
        rm dockerize-alpine-linux-amd64-v$DOCKERIZE_VERSION.tar.gz
        chmod +x /usr/local/bin/dockerize
    fi

    if [[ ! -x "$(command -v composer)" ]]; then
        echo "=========================================================="
        echo " INSTALL COMPOSER"
        echo "=========================================================="
        curl -o /usr/local/bin/composer https://getcomposer.org/download/$COMPOSER_VERSION/composer.phar
        chmod +x /usr/local/bin/composer
        mkdir -p $HOME/.composer/vendor/bin
        chown -R $USERNAME:$USERGROUP $HOME/.composer
        XPATH+=":$HOME/.composer/vendor/bin"
    fi

    # SETUP SSH
    echo "=========================================================="
    echo " SETUP SSH"
    echo "=========================================================="
    sed -ri "s/^#Port 22/Port ${SSH_PORT}/g" /etc/ssh/sshd_config
    sed -ri 's/^#ListenAddress\s0+.*/ListenAddress 0\.0\.0\.0/' /etc/ssh/sshd_config
    sed -ri 's/^#HostKey \/etc\/ssh\/ssh_host_rsa_key/HostKey \/etc\/ssh\/ssh_host_rsa_key/g' /etc/ssh/sshd_config
    sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -ri 's/^#?RSAAuthentication\s+.*/RSAAuthentication yes/' /etc/ssh/sshd_config
    sed -ri 's/^#?PubkeyAuthentication\s+.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    mkdir -p $HOME/.ssh
    /usr/bin/ssh-keygen -A &> /dev/null

    echo "SSH Login on Port : ${SSH_PORT}"
    if [[ -v SSH_PUBLIC_KEY ]]; then
        sed -ri 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        echo "${SSH_PUBLIC_KEY}" > $HOME/.ssh/authorized_keys
        chmod 600 $HOME/.ssh/authorized_keys
        echo "SSH Authentication with Public Key enabled."
    elif [[ -v SSH_PASSWORD ]]; then
        echo "${USERNAME}:${SSH_PASSWORD}" | chpasswd &> /dev/null
        echo "SSH Authentication with password enabled."
    else
        echo "SSH password login enabled:"
        echo "Username: ${USERNAME}"
        echo "Password: ${RANDPASS}"
    fi
    chmod 700 $HOME/.ssh
    chown -R $USERNAME:$USERGROUP $HOME/.ssh
    echo " "

    # SETUP NGINX
    echo "=========================================================="
    echo " SETUP NGINX"
    echo "=========================================================="
    mkdir -p $HOME/logs
    mkdir -p /var/cache/nginx
    touch $HOME/logs/access.log
    chown -R $USERNAME:$USERGROUP /var/lib/nginx
    chown -R $USERNAME:$USERGROUP /var/tmp/nginx
    chown -R $USERNAME:$USERGROUP /var/log/nginx
    chown -R $USERNAME:$USERGROUP /var/cache/nginx
    echo "Creating nginx.conf from template..."
    dockerize -template /template/nginx-conf.tmpl:/etc/nginx/nginx.conf
    echo "Creating grav.conf from template..."
    dockerize -template /template/grav-conf.tmpl:/etc/nginx/conf.d/grav.conf
    echo "Grav host configuration location: /etc/nginx/conf.d/grav.conf"
    echo " "

    # SETUP PHP
    echo "=========================================================="
    echo " SETUP PHP"
    echo "=========================================================="
    mkdir -p /var/lib/php
    chown -R $USERNAME:$USERGROUP /var/lib/php
    rm /usr/local/etc/php-fpm.d/*.conf
    dockerize -template /template/php-fpm-pool.tmpl:/usr/local/etc/php-fpm.d/www.conf
    dockerize -template /template/php-extra.tmpl:$PHP_INI_DIR/conf.d/00-custom.ini
    dockerize -template /template/opcache.ini.tmpl:$PHP_INI_DIR/conf.d/10-opcache.ini
    if [[ -f "${PHP_INI_DIR}/php.ini-production" ]]; then
        cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
    fi
    PHP_CLI_PATH=$(which php)
    echo "PHP Configuration Location: ${PHP_INI_DIR}/php.ini"
    echo "PHP binary path: ${PHP_CLI_PATH}"
    echo " "

    # INSTALL GRAV
    if [[ ! -d "${HOME}/grav" || ! -f "${HOME}/grav/index.php" ]]; then
        echo "=========================================================="
        echo " INSTALL GRAV"
        echo "=========================================================="
        cd $HOME
        wget -qO $HOME/grav.zip "https://github.com/getgrav/grav/releases/download/${GRAV_VERSION}/grav-v${GRAV_VERSION}.zip"
        unzip -qq $HOME/grav.zip -d $HOME && rm $HOME/grav.zip
        if [[ ! -d "${HOME}/grav" ]]; then
            echo "GRAV Installation directory not exits. Exiting.."
            ls -la $HOME
            exit 1
        fi
        echo "GRAV Successfully installed at: ${HOME}/grav"
        chown -R $USERNAME:$USERGROUP $HOME/grav
        if [[ -v ADMIN_USERNAME && -v ADMIN_PASSWORD && -v ADMIN_EMAIL ]]; then
            echo "Installing admin plugin and creating new admin user: ${ADMIN_USERNAME} ..."
            su - $USERNAME -c "set php=${PHP_CLI_PATH} ${HOME}/bin/gpm install admin -y"
            su - $USERNAME -c "set php=${PHP_CLI_PATH} ${HOME}/bin/grav plugin login newuser -P a -t Administrator -u ${ADMIN_USERNAME} -e ${ADMIN_EMAIL} -p ${ADMIN_PASSWORD}"
        fi
    fi
    echo " "
    if [[ -d "${HOME}/grav/bin" ]]; then
        XPATH+=":$HOME/grav/bin"
    fi

    # INSTALL NODEJS YARN
    echo "=========================================================="
    echo " INSTALL YARN"
    echo "=========================================================="
    if [[ "${INSTALL_YARN}" == '1' ]]; then
        su - $USERNAME -c "curl -o- -L https://yarnpkg.com/install.sh | bash"
        echo "Yarn located at: ${HOME}/.yarn/bin/yarn and added to your PATH"
        echo "Installing gulp ..."
        su - $USERNAME -c "$HOME/.yarn/bin/yarn global add gulp-cli"
        XPATH+=":$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin"
    fi
    echo " "

    # GET OWNERSHIP AND PATH
    echo "PATH=\$PATH${XPATH}" >> $HOME/.profile
    chown -R $USERNAME:$USERGROUP $HOME

    # MARK CONTAINER AS INSTALLED
    echo "=========================================================="
    echo " SETUP DONE ;) CONITNUE SERVICES"
    echo "=========================================================="
    touch /etc/.setupdone
    echo " "
fi

/usr/bin/supervisord -n -c /etc/supervisord.conf

exec "$@"
