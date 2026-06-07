(function() {
  var hamburger = document.getElementById('hamburger');
  var navLinks  = document.getElementById('navLinks');
  if (!hamburger || !navLinks) return;

  hamburger.setAttribute('aria-expanded', 'false');

  hamburger.addEventListener('click', function() {
    var isOpen = navLinks.classList.toggle('open');
    hamburger.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
  });

  navLinks.querySelectorAll('a').forEach(function(a) {
    a.addEventListener('click', function() {
      navLinks.classList.remove('open');
      hamburger.setAttribute('aria-expanded', 'false');
    });
  });
})();
