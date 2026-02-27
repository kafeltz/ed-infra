<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>EasyDoor — Criar Conta</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css"/>
  <link rel="icon" type="image/jpeg" href="${url.resourcesPath}/img/easydoor-logo.jpeg"/>
</head>
<body class="login-pf-page">
<div class="container-fluid">
  <div id="kc-content">

    <div class="ed-logo-wrapper">
      <img src="${url.resourcesPath}/img/easydoor-logo.jpeg" alt="EasyDoor" class="ed-logo"/>
    </div>

    <div id="kc-page-title">Criar sua conta</div>
    <div class="ed-subtitle">Preencha os dados para se cadastrar</div>

    <#if message?has_content>
      <div class="alert alert-${message.type}">
        ${message.summary?no_esc}
      </div>
    </#if>

    <form id="kc-register-form" action="${url.registrationAction}" method="post">

      <div class="form-group <#if messagesPerField.existsError("firstName")>has-error</#if>">
        <label for="firstName">Nome</label>
        <input
          id="firstName"
          name="firstName"
          type="text"
          class="form-control"
          value="${(register.formData.firstName)!""}"
          autocomplete="given-name"
          autofocus
        />
        <#if messagesPerField.existsError("firstName")>
          <span class="help-block error-msg">${messagesPerField.get("firstName")?no_esc}</span>
        </#if>
      </div>

      <div class="form-group <#if messagesPerField.existsError("lastName")>has-error</#if>">
        <label for="lastName">Sobrenome</label>
        <input
          id="lastName"
          name="lastName"
          type="text"
          class="form-control"
          value="${(register.formData.lastName)!""}"
          autocomplete="family-name"
        />
        <#if messagesPerField.existsError("lastName")>
          <span class="help-block error-msg">${messagesPerField.get("lastName")?no_esc}</span>
        </#if>
      </div>

      <div class="form-group <#if messagesPerField.existsError("email")>has-error</#if>">
        <label for="email">E-mail</label>
        <input
          id="email"
          name="email"
          type="email"
          class="form-control"
          value="${(register.formData.email)!""}"
          autocomplete="email"
        />
        <#if messagesPerField.existsError("email")>
          <span class="help-block error-msg">${messagesPerField.get("email")?no_esc}</span>
        </#if>
      </div>

      <#if !realm.registrationEmailAsUsername>
        <div class="form-group <#if messagesPerField.existsError("username")>has-error</#if>">
          <label for="username">Usuário</label>
          <input
            id="username"
            name="username"
            type="text"
            class="form-control"
            value="${(register.formData.username)!""}"
            autocomplete="username"
          />
          <#if messagesPerField.existsError("username")>
            <span class="help-block error-msg">${messagesPerField.get("username")?no_esc}</span>
          </#if>
        </div>
      </#if>

      <div class="form-group <#if messagesPerField.existsError("password","password-confirm")>has-error</#if>">
        <label for="password">Senha</label>
        <input
          id="password"
          name="password"
          type="password"
          class="form-control"
          autocomplete="new-password"
        />
        <#if messagesPerField.existsError("password")>
          <span class="help-block error-msg">${messagesPerField.get("password")?no_esc}</span>
        </#if>
      </div>

      <div class="form-group <#if messagesPerField.existsError("password-confirm")>has-error</#if>">
        <label for="password-confirm">Confirmar senha</label>
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

      <button type="submit" id="kc-register" class="btn btn-primary">Criar conta</button>
    </form>

    <div id="kc-registration">
      Já tem uma conta?
      <a href="${url.loginUrl}">Entrar</a>
    </div>

  </div>
</div>
</body>
</html>
