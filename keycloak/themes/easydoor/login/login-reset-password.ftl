<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>EasyDoor — Recuperar Senha</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css"/>
  <link rel="icon" type="image/jpeg" href="${url.resourcesPath}/img/easydoor-logo.jpeg"/>
</head>
<body class="login-pf-page">
<div class="container-fluid">
  <div id="kc-content">

    <div class="ed-logo-wrapper">
      <img src="${url.resourcesPath}/img/easydoor-logo.jpeg" alt="EasyDoor" class="ed-logo"/>
    </div>

    <div id="kc-page-title">Recuperar senha</div>
    <div class="ed-subtitle">Informe seu e-mail para receber o link de redefinição</div>

    <#if message?has_content>
      <div class="alert alert-${message.type}">
        ${message.summary?no_esc}
      </div>
    </#if>

    <form id="kc-reset-password-form" action="${url.loginAction}" method="post">

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
          value="${(auth.attemptedUsername)!""}"
          autocomplete="username"
          autofocus
        />
      </div>

      <button type="submit" id="kc-reset-password-button" class="btn btn-primary">
        Enviar link de recuperação
      </button>
    </form>

    <div id="kc-registration">
      Lembrou a senha?
      <a href="${url.loginUrl}">Voltar ao login</a>
    </div>

  </div>
</div>
</body>
</html>
