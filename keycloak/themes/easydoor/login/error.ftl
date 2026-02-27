<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>EasyDoor — Erro</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css"/>
  <link rel="icon" type="image/jpeg" href="${url.resourcesPath}/img/easydoor-logo.jpeg"/>
</head>
<body class="login-pf-page">
<div class="container-fluid">
  <div id="kc-content">

    <div class="ed-logo-wrapper">
      <img src="${url.resourcesPath}/img/easydoor-logo.jpeg" alt="EasyDoor" class="ed-logo"/>
    </div>

    <div class="ed-error-icon">&#x26A0;</div>

    <div id="kc-page-title">Ocorreu um erro</div>

    <#if message?has_content>
      <div class="alert alert-error" style="margin-top:20px;">
        ${message.summary?no_esc}
      </div>
    </#if>

    <div id="kc-registration">
      <a href="${url.loginUrl}">Voltar ao login</a>
    </div>

  </div>
</div>
</body>
</html>
