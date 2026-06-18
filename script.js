/* ============================================================
   Jire Orinoco — interacción: tema, idioma, animaciones, form
   ============================================================ */

/* ---------- i18n ---------- */
const I18N = {
  es: {
    "meta.title": "Jire Orinoco · Energía que mueve a Venezuela",
    "meta.description": "Jire Orinoco — Energía y petróleo de Venezuela para el mundo. Exploración, producción y refinación responsable.",
    "nav.about": "Nosotros", "nav.services": "Servicios", "nav.impact": "Impacto",
    "nav.sustainability": "Sostenibilidad", "nav.contact": "Contacto",
    "hero.eyebrow": "Faja Petrolífera del Orinoco · Venezuela",
    "hero.title": "Energía que mueve a Venezuela hacia el futuro",
    "hero.sub": "Exploramos, producimos y refinamos petróleo con tecnología de vanguardia y compromiso con las comunidades y el ambiente.",
    "hero.cta1": "Trabajemos juntos", "hero.cta2": "Conoce nuestros servicios",
    "hero.badge1": "+40 años de experiencia", "hero.badge2": "Operaciones 24/7",
    "hero.badge3": "Estándares HSE internacionales",
    "about.kicker": "Nosotros", "about.title": "Una empresa venezolana con visión global",
    "about.p1": "Desde el corazón de la Faja Petrolífera del Orinoco, integramos toda la cadena de valor del petróleo: desde la exploración geológica hasta la entrega del producto final a mercados internacionales.",
    "about.p2": "Nuestra gente, tecnología y procesos están alineados con los más altos estándares de seguridad, calidad y responsabilidad ambiental.",
    "about.v1t": "Cadena integrada", "about.v1p": "Upstream, midstream y downstream bajo un mismo techo.",
    "about.v2t": "Tecnología", "about.v2p": "Monitoreo digital y analítica de datos en tiempo real.",
    "about.v3t": "Comunidad", "about.v3p": "Inversión social en las regiones donde operamos.",
    "services.kicker": "Servicios", "services.title": "Lo que hacemos",
    "services.desc": "Soluciones integrales a lo largo de toda la cadena energética.",
    "services.s1t": "Exploración", "services.s1p": "Estudios geológicos y sísmicos para localizar reservas con precisión.",
    "services.s2t": "Producción", "services.s2p": "Extracción eficiente de crudo pesado y extrapesado del Orinoco.",
    "services.s3t": "Refinación", "services.s3p": "Procesamiento y mejoramiento de crudo en derivados de alto valor.",
    "services.s4t": "Logística", "services.s4p": "Transporte y distribución segura a mercados nacionales e internacionales.",
    "stats.s1": "Barriles producidos / día", "stats.s2": "Años de trayectoria",
    "stats.s3": "Colaboradores", "stats.s4": "Mercados de exportación",
    "susta.kicker": "Sostenibilidad", "susta.title": "Energía hoy, responsabilidad para mañana",
    "susta.p1": "Reducimos nuestra huella ambiental con captura de gas, reinyección de agua y programas de reforestación en zonas de operación.",
    "susta.l1": "Reducción progresiva de emisiones de carbono",
    "susta.l2": "Gestión responsable del agua y los suelos",
    "susta.l3": "Transición gradual hacia energías más limpias",
    "contact.title": "Construyamos el futuro energético juntos",
    "contact.desc": "Cuéntanos tu proyecto y un especialista te contactará.",
    "contact.name": "Nombre", "contact.email": "Correo electrónico", "contact.message": "Mensaje",
    "contact.submit": "Enviar mensaje", "contact.note": "¡Gracias! Te contactaremos pronto.",
    "footer.tagline": "Energía y petróleo de Venezuela para el mundo.",
    "footer.address": "Puerto Ordaz, Estado Bolívar · Venezuela",
    "footer.rights": "Todos los derechos reservados."
  },
  en: {
    "meta.title": "Jire Orinoco · Energy that powers Venezuela",
    "meta.description": "Jire Orinoco — Venezuelan energy and oil for the world. Responsible exploration, production and refining.",
    "nav.about": "About", "nav.services": "Services", "nav.impact": "Impact",
    "nav.sustainability": "Sustainability", "nav.contact": "Contact",
    "hero.eyebrow": "Orinoco Oil Belt · Venezuela",
    "hero.title": "Energy that powers Venezuela into the future",
    "hero.sub": "We explore, produce and refine oil with cutting-edge technology and a commitment to communities and the environment.",
    "hero.cta1": "Let's work together", "hero.cta2": "Explore our services",
    "hero.badge1": "40+ years of experience", "hero.badge2": "24/7 operations",
    "hero.badge3": "International HSE standards",
    "about.kicker": "About us", "about.title": "A Venezuelan company with a global vision",
    "about.p1": "From the heart of the Orinoco Oil Belt, we integrate the entire oil value chain: from geological exploration to delivering the final product to international markets.",
    "about.p2": "Our people, technology and processes are aligned with the highest standards of safety, quality and environmental responsibility.",
    "about.v1t": "Integrated chain", "about.v1p": "Upstream, midstream and downstream under one roof.",
    "about.v2t": "Technology", "about.v2p": "Digital monitoring and real-time data analytics.",
    "about.v3t": "Community", "about.v3p": "Social investment in the regions where we operate.",
    "services.kicker": "Services", "services.title": "What we do",
    "services.desc": "End-to-end solutions across the entire energy value chain.",
    "services.s1t": "Exploration", "services.s1p": "Geological and seismic studies to locate reserves with precision.",
    "services.s2t": "Production", "services.s2p": "Efficient extraction of heavy and extra-heavy crude from the Orinoco.",
    "services.s3t": "Refining", "services.s3p": "Processing and upgrading crude into high-value derivatives.",
    "services.s4t": "Logistics", "services.s4p": "Safe transport and distribution to domestic and international markets.",
    "stats.s1": "Barrels produced / day", "stats.s2": "Years of experience",
    "stats.s3": "Team members", "stats.s4": "Export markets",
    "susta.kicker": "Sustainability", "susta.title": "Energy today, responsibility for tomorrow",
    "susta.p1": "We reduce our environmental footprint with gas capture, water reinjection and reforestation programs in our operating areas.",
    "susta.l1": "Progressive reduction of carbon emissions",
    "susta.l2": "Responsible management of water and soil",
    "susta.l3": "Gradual transition toward cleaner energy",
    "contact.title": "Let's build the energy future together",
    "contact.desc": "Tell us about your project and a specialist will reach out.",
    "contact.name": "Name", "contact.email": "Email", "contact.message": "Message",
    "contact.submit": "Send message", "contact.note": "Thank you! We'll be in touch soon.",
    "footer.tagline": "Venezuelan energy and oil for the world.",
    "footer.address": "Puerto Ordaz, Bolívar State · Venezuela",
    "footer.rights": "All rights reserved."
  }
};

/* ---------- Theme ---------- */
const root = document.documentElement;
const themeToggle = document.getElementById("themeToggle");

function applyTheme(theme) {
  root.setAttribute("data-theme", theme);
  try { localStorage.setItem("jo-theme", theme); } catch (e) {}
}
(function initTheme() {
  let saved;
  try { saved = localStorage.getItem("jo-theme"); } catch (e) {}
  if (!saved) {
    saved = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  applyTheme(saved);
})();
themeToggle.addEventListener("click", () => {
  applyTheme(root.getAttribute("data-theme") === "dark" ? "light" : "dark");
});

/* ---------- Language ---------- */
const langToggle = document.getElementById("langToggle");

function applyLang(lang) {
  const dict = I18N[lang] || I18N.es;
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    const val = dict[key];
    if (val == null) return;
    if (key === "meta.description") el.setAttribute("content", val);
    else el.textContent = val;
  });
  root.setAttribute("lang", lang);
  document.querySelectorAll(".lang-opt").forEach((o) =>
    o.classList.toggle("active", o.dataset.lang === lang)
  );
  try { localStorage.setItem("jo-lang", lang); } catch (e) {}
}
(function initLang() {
  let saved;
  try { saved = localStorage.getItem("jo-lang"); } catch (e) {}
  if (!saved) saved = (navigator.language || "es").toLowerCase().startsWith("en") ? "en" : "es";
  applyLang(saved);
})();
langToggle.addEventListener("click", () => {
  applyLang(root.getAttribute("lang") === "en" ? "es" : "en");
});

/* ---------- Scroll reveal ---------- */
const revealEls = document.querySelectorAll(".section, .hero-inner");
revealEls.forEach((el) => el.classList.add("reveal"));
const io = new IntersectionObserver((entries) => {
  entries.forEach((e) => {
    if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  });
}, { threshold: 0.12 });
revealEls.forEach((el) => io.observe(el));

/* ---------- Animated counters ---------- */
const counters = document.querySelectorAll(".stat-num");
const countIO = new IntersectionObserver((entries) => {
  entries.forEach((e) => {
    if (!e.isIntersecting) return;
    const el = e.target;
    const target = parseInt(el.dataset.count, 10);
    const suffix = el.dataset.suffix || "";
    const start = performance.now();
    const dur = 1400;
    function tick(now) {
      const p = Math.min((now - start) / dur, 1);
      const eased = 1 - Math.pow(1 - p, 3);
      el.textContent = Math.round(target * eased).toLocaleString() + suffix;
      if (p < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    countIO.unobserve(el);
  });
}, { threshold: 0.5 });
counters.forEach((c) => countIO.observe(c));

/* ---------- Contact form ---------- */
const form = document.getElementById("contactForm");
const note = document.getElementById("formNote");
form.addEventListener("submit", (e) => {
  e.preventDefault();
  if (!form.checkValidity()) { form.reportValidity(); return; }
  note.hidden = false;
  form.querySelectorAll("input, textarea").forEach((f) => (f.value = ""));
});

/* ---------- Footer year ---------- */
document.getElementById("year").textContent = new Date().getFullYear();
