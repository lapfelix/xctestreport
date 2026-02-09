(function() {
  var coll = document.getElementsByClassName('collapsible');
  var i;

  for (i = 0; i < coll.length; i++) {
    var content = coll[i].nextElementSibling;
    if (content) {
      content.style.display = 'block';
    }
  }

  for (i = 0; i < coll.length; i++) {
    coll[i].addEventListener('click', function() {
      this.classList.toggle('collapsed');
    });
  }

  var toggleAllBtn = document.getElementById('toggle-all');
  if (!toggleAllBtn) {
    return;
  }

  toggleAllBtn.textContent = 'Collapse All';
  toggleAllBtn.addEventListener('click', function() {
    var expanded = toggleAllBtn.textContent === 'Collapse All';
    for (i = 0; i < coll.length; i++) {
      if (expanded) {
        coll[i].classList.add('collapsed');
      } else {
        coll[i].classList.remove('collapsed');
      }
    }
    toggleAllBtn.textContent = expanded ? 'Expand All' : 'Collapse All';
  });
})();
