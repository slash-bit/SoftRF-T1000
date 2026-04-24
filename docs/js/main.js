// SoftRF-PG Documentation - Main JS

document.addEventListener('DOMContentLoaded', function() {
  // Mobile menu toggle
  const toggle = document.querySelector('.menu-toggle');
  const nav = document.querySelector('.top-nav');
  if (toggle && nav) {
    toggle.addEventListener('click', function() {
      nav.classList.toggle('open');
    });
    // Close menu when clicking a link
    nav.querySelectorAll('a').forEach(function(a) {
      a.addEventListener('click', function() {
        nav.classList.remove('open');
      });
    });
  }

  // Back to top button
  const btn = document.querySelector('.back-to-top');
  if (btn) {
    window.addEventListener('scroll', function() {
      btn.classList.toggle('visible', window.scrollY > 300);
    });
  }

  // Active sidebar link highlighting on scroll
  const sidebarLinks = document.querySelectorAll('.sidebar-nav a[href^="#"]');
  if (sidebarLinks.length > 0) {
    const sections = [];
    sidebarLinks.forEach(function(link) {
      var id = link.getAttribute('href').slice(1);
      var el = document.getElementById(id);
      if (el) sections.push({ el: el, link: link });
    });

    function updateActive() {
      var scrollY = window.scrollY + 80;
      var current = null;
      for (var i = 0; i < sections.length; i++) {
        if (sections[i].el.offsetTop <= scrollY) {
          current = sections[i];
        }
      }
      sidebarLinks.forEach(function(l) { l.classList.remove('active'); });
      if (current) current.link.classList.add('active');
    }

    window.addEventListener('scroll', updateActive);
    updateActive();
  }
});
