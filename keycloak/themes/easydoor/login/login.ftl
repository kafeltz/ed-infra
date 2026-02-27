<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>EasyDoor — Entrar</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css"/>
  <link rel="icon" type="image/jpeg" href="${url.resourcesPath}/img/easydoor-logo.jpeg"/>
</head>
<body class="login-pf-page">
<div class="container-fluid">
  <div id="kc-content">

    <div class="ed-logo-wrapper">
      <img src="${url.resourcesPath}/img/easydoor-logo.jpeg" alt="EasyDoor" class="ed-logo"/>
    </div>

    <div id="kc-page-title">Bem-vindo de volta</div>
    <div class="ed-subtitle">Entre na sua conta EasyDoor</div>

    <#if message?has_content>
      <div class="alert alert-${message.type}">
        ${message.summary?no_esc}
      </div>
    </#if>

    <form id="kc-form-login" action="${url.loginAction}" method="post">

      <div class="form-group">
        <label for="username">
          <#if realm.loginWithEmailAllowed && !realm.registrationEmailAsUsername>
            E-mail ou usuário
          <#else>
            E-mail
          </#if>
        </label>
        <input
          id="username"
          name="username"
          type="text"
          class="form-control"
          value="${(login.username)!""}"
          autocomplete="username"
          autofocus
        />
      </div>

      <div class="form-group">
        <label for="password">Senha</label>
        <input
          id="password"
          name="password"
          type="password"
          class="form-control"
          autocomplete="current-password"
        />
      </div>

      <div id="kc-form-options">
        <#if realm.rememberMe>
          <div class="checkbox">
            <input type="checkbox" id="rememberMe" name="rememberMe"
              <#if login.rememberMe??>checked</#if>/>
            <label for="rememberMe">Lembrar-me</label>
          </div>
        <#else>
          <span></span>
        </#if>

        <#if realm.resetPasswordAllowed>
          <a href="${url.loginResetCredentialsUrl}" tabindex="5">Esqueci minha senha</a>
        </#if>
      </div>

      <input type="hidden" id="id-hidden-input" name="credentialId"
        <#if auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if>/>

      <button type="submit" id="kc-login" class="btn btn-primary">Entrar</button>
    </form>

    <#if realm.registrationAllowed>
      <div id="kc-registration">
        Não tem uma conta?
        <a href="${url.registrationUrl}">Criar conta</a>
      </div>
    </#if>

  </div>
</div>
</body>
</html>
