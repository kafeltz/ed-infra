<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>EasyDoor — Verificar E-mail</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css"/>
  <link rel="icon" type="image/jpeg" href="${url.resourcesPath}/img/easydoor-logo.jpeg"/>
</head>
<body class="login-pf-page">
<div class="container-fluid">
  <div id="kc-content">

    <div class="ed-logo-wrapper">
      <img src="${url.resourcesPath}/img/easydoor-logo.jpeg" alt="EasyDoor" class="ed-logo"/>
    </div>

    <div id="kc-page-title">Verifique seu e-mail</div>

    <#if message?has_content>
      <div class="alert alert-${message.type}">
        ${message.summary?no_esc}
      </div>
    </#if>

    <div class="ed-info-text">
      <p>Enviamos um link de verificação para</p>
      <p><strong>${(user.email)!""}</strong></p>
      <p style="margin-top:12px;">Clique no link do e-mail para ativar sua conta. Verifique também a pasta de spam.</p>
    </div>

    <form action="${url.loginAction}" method="post">
      <button type="submit" class="btn btn-primary">
        Reenviar e-mail de verificação
      </button>
    </form>

    <div id="kc-registration">
      <a href="${url.loginUrl}">Voltar ao login</a>
    </div>

  </div>
</div>
</body>
</html>
