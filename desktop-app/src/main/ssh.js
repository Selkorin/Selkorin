'use strict';
// Тонкая обёртка над ssh2: подключение по ключу/паролю, выполнение команд,
// потоковый вывод и загрузка файлов по SFTP. Без внешних сервисов.
const { Client } = require('ssh2');
const fs = require('fs');

function connect(profile) {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    const cfg = {
      host: profile.host,
      port: Number(profile.port) || 22,
      username: profile.username || 'root',
      readyTimeout: 20000,
      keepaliveInterval: 10000,
    };
    const auth = profile.auth || {};
    if (auth.type === 'password') {
      cfg.password = auth.password || '';
    } else {
      // авторизация по приватному ключу
      try {
        cfg.privateKey = fs.readFileSync(auth.keyPath || `${process.env.HOME}/.ssh/id_ed25519`);
      } catch (e) {
        return reject(new Error(`Не удалось прочитать SSH-ключ: ${e.message}`));
      }
      if (auth.passphrase) cfg.passphrase = auth.passphrase;
    }
    conn.on('ready', () => resolve(conn));
    conn.on('error', (err) => reject(err));
    conn.connect(cfg);
  });
}

// Префикс sudo для не-root пользователей
function sudo(profile, cmd) {
  const isRoot = (profile.username || 'root') === 'root';
  if (isRoot) return cmd;
  // -n: не спрашивать пароль (нужен passwordless sudo). Если задан пароль sudo — прокидываем через -S.
  const sp = (profile.auth && profile.auth.sudoPassword) || '';
  if (sp) return `echo ${shellQuote(sp)} | sudo -S -p '' bash -c ${shellQuote(cmd)}`;
  return `sudo -n bash -c ${shellQuote(cmd)}`;
}

function shellQuote(s) {
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

// Выполнить команду, вернуть {code, stdout, stderr}
function exec(conn, cmd) {
  return new Promise((resolve, reject) => {
    conn.exec(cmd, (err, stream) => {
      if (err) return reject(err);
      let stdout = '';
      let stderr = '';
      stream
        .on('close', (code) => resolve({ code, stdout, stderr }))
        .on('data', (d) => (stdout += d.toString()))
        .stderr.on('data', (d) => (stderr += d.toString()));
    });
  });
}

// Выполнить команду с потоковым выводом (для установки). onData(line)
function execStream(conn, cmd, onData) {
  return new Promise((resolve, reject) => {
    conn.exec(cmd, { pty: true }, (err, stream) => {
      if (err) return reject(err);
      let all = '';
      const push = (d) => {
        const s = d.toString();
        all += s;
        if (onData) onData(s);
      };
      stream
        .on('close', (code) => resolve({ code, output: all }))
        .on('data', push)
        .stderr.on('data', push);
    });
  });
}

// Загрузить локальный файл на сервер по SFTP
function sftpPut(conn, localPath, remotePath, mode = 0o755) {
  return new Promise((resolve, reject) => {
    conn.sftp((err, sftp) => {
      if (err) return reject(err);
      sftp.fastPut(localPath, remotePath, {}, (e) => {
        if (e) return reject(e);
        sftp.chmod(remotePath, mode, (ce) => (ce ? reject(ce) : resolve(true)));
      });
    });
  });
}

module.exports = { connect, exec, execStream, sftpPut, sudo, shellQuote };
