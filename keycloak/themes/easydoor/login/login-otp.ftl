<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>EasyDoor — Autenticação em Dois Fatores</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css"/>
  <link rel="icon" type="image/jpeg" href="${url.resourcesPath}/img/easydoor-logo.jpeg"/>
</head>
<body class="login-pf-page">
<div class="container-fluid">
  <div id="kc-content">

    <div class="ed-logo-wrapper">
      <img src="${url.resourcesPath}/img/easydoor-logo.jpeg" alt="EasyDoor" class="ed-logo"/>
    </div>

    <div id="kc-page-title">Autenticação em dois fatores</div>
    <div class="ed-subtitle">Insira o código do seu autenticador</div>

    <#if message?has_content>
      <div class="alert alert-${message.type}">
        ${message.summary?no_esc}
      </div>
    </#if>

    <form id="kc-otp-login-form" action="${url.loginAction}" method="post">

      <#if otpLogin.userOtpCredentials?size gt 1>
        <div class="form-group">
          <label>Selecionar autenticador</label>
          <#list otpLogin.userOtpCredentials as otpCredential>
            <div class="ed-checkbox-row">
              <input
                type="radio"
                id="kc-otp-credential-${otpCredential?index}"
                name="selectedCredentialId"
                value="${otpCredential.id}"
                <#if otpCredential.id == otpLogin.selectedCredentialId>checked</#if>
              />
              <label for="kc-otp-credential-${otpCredential?index}">
                ${otpCredential.userLabel!"Autenticador ${otpCredential?index + 1}"}
              </label>
            </div>
          </#list>
        </div>
      </#if>

      <div class="form-group otp-grid">
        <label for="otp">Código de verificação</label>
        <input
          id="otp"
          name="otp"
          type="text"
          class="form-control"
          autocomplete="one-time-code"
          inputmode="numeric"
          autofocus
          placeholder="000 000"
        />
      </div>

      <button type="submit" class="btn btn-primary">Verificar</button>
    </form>

    <div id="kc-registration">
      <a href="${url.loginUrl}">Cancelar</a>
    </div>

  </div>
</div>
</body>
</html>
