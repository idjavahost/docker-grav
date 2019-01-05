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
        wget -q https://github.com/jwilder/dockerize/releases/download/v$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-v$DOCKERIZE_VERSION.tar.gz
        tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-v$DOCKERIZE_VERSION.tar.gz
        rm dockerize-alpine-linux-amd64-v$DOCKERIZE_VERSION.tar.gz
        chmod +x /usr/local/bin/dockerize
    fi

    if [[ ! -x "$(command -v composer)" ]]; then
        curl -o /usr/local/bin/composer https://getcomposer.org/download/$COMPOSER_VERSION/composer.phar
        chmod +x /usr/local/bin/composer
        mkdir -p $HOME/.composer/vendor/bin
        chown -R $USERNAME:$USERGROUP $HOME/.composer
        /usr/local/bin/composer self-update
        XPATH+=":$HOME/.composer/vendor/bin"
    fi

    # SETUP SSH
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
        echo "SSH password login enabled :"
        echo "Username: ${USERNAME}"
        echo "Password: ${RANDPASS}"
    fi
    chmod 700 $HOME/.ssh
    chown -R $USERNAME:$USERGROUP $HOME/.ssh

    # SETUP NGINX
    mkdir -p $HOME/logs
    mkdir -p /var/cache/nginx
    touch $HOME/logs/access.log
    chown -R $USERNAME:$USERGROUP /var/lib/nginx
    chown -R $USERNAME:$USERGROUP /var/tmp/nginx
    chown -R $USERNAME:$USERGROUP /var/log/nginx
    chown -R $USERNAME:$USERGROUP /var/cache/nginx
    dockerize -template /template/nginx-conf.tmpl:/etc/nginx/nginx.conf
    dockerize -template /template/grav.tmpl:/etc/nginx/conf.d/grav.conf

    # SETUP PHP
    mkdir -p /var/lib/php
    chown -R $USERNAME:$USERGROUP /var/lib/php
    rm /usr/local/etc/php-fpm.d/*.conf
    dockerize -template /template/php-fpm-pool.tmpl:/usr/local/etc/php-fpm.d/www.conf
    dockerize -template /template/php-extra.tmpl:$PHP_INI_DIR/conf.d/00-custom.ini
    dockerize -template /template/opcache.ini.tmpl:$PHP_INI_DIR/conf.d/10-opcache.ini

    if [[ -f "${PHP_INI_DIR}/php.ini-production" ]]; then
        cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
    fi

    # INSTALL GRAV
    if [[ ! -d "${HOME}/grav" || ! -f "${HOME}/grav/index.php" ]]; then
        mkdir -p $HOME/grav
        su - $USERNAME -c "composer create-project getgrav/grav ${HOME}/grav"
        chmod +x $HOME/grav/bin/* && cd $HOME/grav
        su - $USERNAME -c "${HOME}/bin/grav install"
        if [[ -v ADMIN_USERNAME && -v ADMIN_PASSWORD && -v ADMIN_EMAIL ]]; then
            su - $USERNAME -c "${HOME}/bin/gpm install admin -y"
            su - $USERNAME -c "${HOME}/bin/grav plugin login newuser -P a -t Administrator -u ${ADMIN_USERNAME} -e ${ADMIN_EMAIL} -p ${ADMIN_PASSWORD}"
        fi
    fi

    if [[ -d "${HOME}/grav/bin" ]]; then
        XPATH+=":$HOME/grav/bin"
    fi

    # GET OWNERSHIP AND PATH
    echo "PATH=\$PATH${XPATH}" >> $HOME/.profile
    chown -R $USERNAME:$USERGROUP $HOME

    # INSTALL NODEJS YARN
    if [[ "${INSTALL_YARN}" == '1' ]]; then
        su - $USERNAME -c "curl -o- -L https://yarnpkg.com/install.sh | bash"
        echo "export PATH=\$HOME/.yarn/bin:\$HOME/.config/yarn/global/node_modules/.bin:\$PATH" >> $HOME/.bash_profile
        su - $USERNAME -c "$HOME/.yarn/bin/yarn global add gulp-cli"
    fi

    # MARK CONTAINER AS INSTALLED
    touch /etc/.setupdone
fi

/usr/bin/supervisord -n -c /etc/supervisord.conf

exec "$@"
