// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import { phoneArtwork, reviewArtwork, screenshot } from './site-components.mjs';

export function homeMoments(lang = 'en') {
  const es = lang === 'es';
  return `<section class="section section-band" aria-labelledby="moments-title">
  <div class="container">
    <div class="section-header section-header--center" data-reveal="fade-up">
      <p class="eyebrow">${es ? 'En la práctica' : 'In practice'}</p>
      <h2 id="moments-title">${es ? 'De la primera instrucción a la revisión final.' : 'From the first prompt to the final review.'}</h2>
    </div>
    <div class="moments">
      <article class="moment" id="moment-agents">
        <div class="moment__copy" data-reveal="fade-up">
          <p class="moment__kicker is-working"><span class="state-dot"></span>${es ? 'Agentes' : 'Agents'}</p>
          <h3>${es ? 'Todas las sesiones de un vistazo.' : 'Every session, one glance.'}</h3>
          <p>${es ? 'El panel de agentes muestra cada sesión con su estado, carpeta, herramienta activa y archivos tocados. Cuando una te necesita, Cocxy te avisa.' : 'The agent panel lists each session with its state, working directory, active tool, and the files it touched. When one needs you, Cocxy lets you know.'}</p>
          <a class="text-link" href="${es ? '/es/features/agents.html' : '/features/agents.html'}">${es ? 'Cómo funciona la detección' : 'How detection works'}</a>
        </div>
        <figure class="moment__media" data-reveal="fade-up">
          <div class="window">
            ${screenshot({ name: 'getting-started-dashboard', width: 800, height: 489, alt: es ? 'Cocxy con dos paneles de terminal y el panel de agentes mostrando una sesión que edita un archivo' : 'Cocxy with two terminal panes and the agent panel showing a session that is editing a file' })}
          </div>
        </figure>
      </article>
      <article class="moment moment--flip" id="moment-review">
        <div class="moment__copy" data-reveal="fade-up">
          <p class="moment__kicker is-waiting"><span class="state-dot"></span>${es ? 'Revisión de código' : 'Code review'}</p>
          <h3>${es ? 'Lee el diff antes de aplicarlo.' : 'Read the diff before it lands.'}</h3>
          <p>${es ? 'Abre el panel de revisión junto a la terminal, comenta cualquier línea, acepta o rechaza cada cambio y devuelve notas estructuradas a la sesión del agente.' : 'Open the review panel beside the terminal, comment on any line, accept or reject each change, and send structured notes straight back to the agent’s session.'}</p>
          <a class="text-link" href="${es ? '/es/features/code-review.html' : '/features/code-review.html'}">${es ? 'Ver la revisión de código' : 'Explore code review'}</a>
        </div>
        <figure class="moment__media" data-reveal="fade-up">
          ${reviewArtwork(lang)}
        </figure>
      </article>
      <article class="moment" id="moment-projects">
        <div class="moment__copy" data-reveal="fade-up">
          <p class="moment__kicker is-done"><span class="state-dot"></span>${es ? 'Proyectos' : 'Projects'}</p>
          <h3>${es ? 'Proyectos, no solo carpetas.' : 'Projects, not just folders.'}</h3>
          <p>${es ? 'Cada repositorio tiene su propio espacio para sesiones, notas y tareas. Clónalo una vez y cada agente que inicies ahí queda con el proyecto.' : 'Each repository gets its own home for sessions, notes, and tasks. Clone it once, and every agent you start there stays with the project.'}</p>
        </div>
        <figure class="moment__media" data-reveal="fade-up">
          <div class="window window--detail">
            ${screenshot({ name: 'getting-started-sidebar', width: 722, height: 441, alt: es ? 'Barra lateral de Cocxy que agrupa sesiones bajo un proyecto' : 'Cocxy sidebar grouping sessions under a project' })}
          </div>
        </figure>
      </article>
      <article class="moment moment--flip" id="moment-mobile">
        <div class="moment__copy" data-reveal="fade-up">
          <p class="moment__kicker is-working"><span class="state-dot"></span>${es ? 'Espejo móvil' : 'Phone mirror'}</p>
          <h3>${es ? 'Tus agentes, en el bolsillo.' : 'Your agents, in your pocket.'}</h3>
          <p>${es ? 'Empareja tu teléfono con un código QR y sigue las sesiones desde su navegador: lee la salida, responde a un agente que te espera o aprueba su siguiente paso. Todo viaja cifrado de extremo a extremo, sin cuenta y sin nube de Cocxy de por medio.' : 'Pair your phone with a QR code and follow sessions from its browser: read the output, answer an agent that is waiting, or approve its next step. Everything travels end-to-end encrypted, with no account and no Cocxy cloud in between.'}</p>
        </div>
        <figure class="moment__media" data-reveal="fade-up">
          ${phoneArtwork(lang)}
        </figure>
      </article>
    </div>
  </div>
</section>`;
}

export function homePrivacy(lang = 'en') {
  const es = lang === 'es';
  return `<section class="section section-band" aria-labelledby="privacy-title">
  <div class="container split-grid">
    <div data-reveal="fade-up">
      <p class="eyebrow">${es ? 'Privacidad verificable' : 'Verifiable privacy'}</p>
      <h2 id="privacy-title">${es ? 'Cero telemetría. Sin cuenta. Sin rastreo.' : 'Zero telemetry. No account. No tracking.'}</h2>
      <p>${es ? 'Cocxy se distribuye sin analíticas, sin subida automática de fallos y sin rastreo oculto. Solo usa la red para lo que tú pides: actualizaciones, navegador, GitHub, SSH, plugins o un teléfono emparejado.' : 'Cocxy ships without analytics, automatic crash upload, or hidden tracking. It reaches the network only for what you ask for: updates, the browser, GitHub, SSH, plugins, or a paired phone.'}</p>
      <a class="text-link" href="${es ? '/es/privacy.html' : '/privacy.html'}">${es ? 'Leer los detalles de privacidad' : 'Read the privacy details'}</a>
    </div>
    <div class="privacy-panel" data-reveal="fade-up">
      <dl class="ledger glass">
        <div><dt>${es ? 'Telemetría' : 'Telemetry'}</dt><dd>${es ? 'Ninguna' : 'None'}</dd></div>
        <div><dt>${es ? 'Analíticas' : 'Analytics'}</dt><dd>${es ? 'Ninguna' : 'None'}</dd></div>
        <div><dt>${es ? 'Subida de fallos' : 'Crash upload'}</dt><dd>${es ? 'Nunca automática' : 'Never automatic'}</dd></div>
        <div><dt>${es ? 'Cuenta' : 'Account'}</dt><dd>${es ? 'No requerida' : 'Not required'}</dd></div>
        <div><dt>${es ? 'Cookies de este sitio' : 'Cookies on this site'}</dt><dd>${es ? 'Ninguna' : 'None'}</dd></div>
      </dl>
    </div>
  </div>
</section>`;
}

export function homeArchitecture(lang = 'en') {
  const es = lang === 'es';
  return `<section class="section" aria-labelledby="architecture-teaser">
  <div class="container split-grid">
    <div data-reveal="fade-up">
      <p class="eyebrow">${es ? 'Arquitectura' : 'Architecture'}</p>
      <h2 id="architecture-teaser">${es ? 'Nativa desde el motor.' : 'Native from the engine up.'}</h2>
      <p>${es ? 'La app separa la interfaz nativa, los servicios de dominio, el manejo de PTY, el renderizado Metal y la ABI C de CocxyCore, para probar cada capa por separado.' : 'The app separates native UI, domain services, PTY handling, Metal rendering, and the CocxyCore C ABI, so each layer can be tested on its own.'}</p>
      <a class="text-link" href="${es ? '/es/architecture.html' : '/architecture.html'}">${es ? 'Ver la arquitectura' : 'View the architecture'}</a>
    </div>
    <img class="architecture-preview" src="/images/architecture-diagram.svg" width="920" height="520" alt="${es ? 'Diagrama de arquitectura de Cocxy: app, paneles, servicios de dominio, CocxyCore, renderizador Metal, capa PTY y almacenes locales' : 'Cocxy architecture diagram: app shell, panels, domain services, CocxyCore, Metal renderer, PTY layer, and local stores'}" loading="lazy" decoding="async" data-reveal="fade-up">
  </div>
</section>`;
}

export function homeDemo(lang = 'en', poster) {
  const es = lang === 'es';
  return `<section class="section section-band" id="demo" aria-labelledby="demo-title">
  <div class="container">
    <div class="section-header section-header--center" data-reveal="fade-up">
      <p class="eyebrow">Demo</p>
      <h2 id="demo-title">${es ? 'Mira una sesión de principio a fin.' : 'Watch a session from start to finish.'}</h2>
      <p>${es ? 'Un recorrido breve por paneles, navegador, Bóveda y estado local, sin scripts de terceros.' : 'A short tour of panes, the browser, Vault, and local state, with no third-party scripts.'}</p>
    </div>
    <div class="window demo__window" data-reveal="fade-up">
      <video controls muted playsinline preload="none" poster="${poster}" width="1280" height="720">
        <source src="/videos/cocxy-demo.webm" type="video/webm">
        <source src="/videos/cocxy-demo.mp4" type="video/mp4">
      </video>
    </div>
  </div>
</section>`;
}

export function homeFaqSection(lang = 'en') {
  const es = lang === 'es';
  return `<section class="section" id="faq" aria-labelledby="home-faq-title">
  <div class="container faq-layout">
    <div class="section-header" data-reveal="fade-up">
      <p class="eyebrow">${es ? 'Preguntas' : 'FAQ'}</p>
      <h2 id="home-faq-title">${es ? 'Antes de instalar.' : 'Before you install.'}</h2>
      <p><a class="text-link" href="${es ? '/es/faq.html' : '/faq.html'}">${es ? 'Todas las preguntas' : 'All questions'}</a></p>
    </div>
    <div class="faq-list" data-reveal="fade-up">
      ${homeFaq(lang).map(([question, answer]) => `<details class="faq-item"><summary>${question}</summary><p>${answer}</p></details>`).join('\n      ')}
    </div>
  </div>
</section>`;
}

export function homeClosing(lang = 'en', logo) {
  const es = lang === 'es';
  return `<section class="section closing" id="opensource" aria-labelledby="opensource-title">
  <div class="container closing__inner" data-reveal="fade-up">
    <div class="closing__icon">${logo}</div>
    <h2 id="opensource-title">${es ? '100% c&oacute;digo abierto, MIT y cero telemetr&iacute;a.' : '100% open source, MIT licensed, zero telemetry.'}</h2>
    <p>${es ? 'Lee cada línea, compílala tú mismo y ayuda a decidir hacia dónde va.' : 'Read every line, build it yourself, and help decide where it goes next.'}</p>
    <div class="hero__actions">
      <a class="button button-primary button-lg" href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">${es ? 'Ver en GitHub' : 'View on GitHub'}</a>
      <a class="button button-secondary button-lg" href="${es ? '/es/docs/' : '/docs/'}">${es ? 'Leer la documentación' : 'Read the docs'}</a>
    </div>
    <dl class="ledger ledger--facts glass">
      <div><dt>${es ? 'Motor' : 'Engine'}</dt><dd>CocxyCore</dd></div>
      <div><dt>${es ? 'Renderizado' : 'Rendering'}</dt><dd>Metal GPU</dd></div>
      <div><dt>${es ? 'Licencia' : 'License'}</dt><dd>MIT</dd></div>
      <div><dt>${es ? 'Idiomas de la app' : 'App languages'}</dt><dd>21</dd></div>
    </dl>
  </div>
</section>`;
}

export function homeFaq(lang = 'en') {
  return lang === 'es' ? [
    ['¿Cocxy requiere cuenta?', 'No. Cocxy se instala y funciona en local sin iniciar sesión.'],
    ['¿Mis sesiones salen de mi Mac?', 'No por telemetría. Cocxy usa la red solo cuando abres el navegador, te conectas por SSH, usas GitHub, buscas actualizaciones, ejecutas plugins o emparejas un teléfono.'],
    ['¿Con qué agentes funciona?', 'Once perfiles integrados cubren las CLI de código más usadas, y puedes añadir cualquier otro agente de línea de comandos en agents.toml.'],
    ['¿Es de código abierto?', 'Sí. Cocxy tiene licencia MIT y su código es público en GitHub.'],
    ['¿Cómo se actualiza?', 'Las versiones están firmadas y notarizadas, y el actualizador integrado instala las nuevas. También puedes actualizar con Homebrew.'],
  ] : [
    ['Does Cocxy require an account?', 'No. Cocxy installs and runs locally without signing in.'],
    ['Do my sessions leave my Mac?', 'Not through telemetry. Cocxy uses the network only when you open the browser, connect over SSH, use GitHub, check for updates, run plugins, or pair a phone.'],
    ['Which agents does it work with?', 'Eleven built-in profiles cover the most popular coding CLIs, and you can add any other command-line agent in agents.toml.'],
    ['Is it open source?', 'Yes. Cocxy is MIT licensed and its source is public on GitHub.'],
    ['How do updates work?', 'Releases are signed and notarized, and the built-in updater installs new versions. You can also upgrade through Homebrew.'],
  ];
}
