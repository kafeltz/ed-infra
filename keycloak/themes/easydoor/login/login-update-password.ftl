<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>EasyDoor — Atualizar Senha</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css"/>
  <link rel="icon" type="image/jpeg" href="${url.resourcesPath}/img/easydoor-logo.jpeg"/>
</head>
<body class="login-pf-page">
<div class="container-fluid">
  <div id="kc-content">

    <div class="ed-logo-wrapper">
      <img src="${url.resourcesPath}/img/easydoor-logo.jpeg" alt="EasyDoor" class="ed-logo"/>
    </div>

    <div id="kc-page-title">Atualizar senha</div>
    <div class="ed-subtitle">Defina uma nova senha para sua conta</div>

    <#if message?has_content>
      <div class="alert alert-${message.type}">
        ${message.summary?no_esc}
      </div>
    </#if>

    <form id="kc-passwd-update-form" action="${url.loginAction}" method="post">

      <input type="hidden" id="username" name="username" value="${username!""}"/>
      <input type="hidden" name="stateChecker" value="${stateChecker!""}"/>

      <div class="form-group <#if messagesPerField.existsError("password","password-confirm")>has-error</#if>">
        <label for="password-new">Nova senha</label>
        <input
          id="password-new"
          name="password-new"
          type="password"
          class="form-control"
          autocomplete="new-password"
          autofocus
        />
        <#if messagesPerField.existsError("password")>
          <span class="help-block error-msg">${messagesPerField.get("password")?no_esc}</span>
        </#if>
      </div>

      <div class="form-group <#if messagesPerField.existsError("password-confirm")>has-error</#if>">
        <label for="password-confirm">Confirmar nova senha</label>
        <input
          id="password-confirm"
          name="password-confirm"
          type="password"
          class="form-control"
          autocomplete="new-password"
        />
        <#if messagesPerField.existsError("password-confirm")>
          <span class="help-block error-msg">${messagesPerField.get("password-confirm")?no_esc}</span>
        </#if>
      </div>

      <div id="kc-form-buttons">
        <button type="submit" class="btn btn-primary">Atualizar senha</button>
      </div>
    </form>

  </div>
</div>
</body>
</html>
