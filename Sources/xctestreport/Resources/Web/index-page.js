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
  if (toggleAllBtn) {
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
  }

  var toggleFailedBtn = document.getElementById('toggle-failed');
  if (toggleFailedBtn) {
    var SHOW_FAILED = 'Show only failed';
    var SHOW_ALL = 'Show all tests';
    var failedOnly = false;
    toggleFailedBtn.textContent = SHOW_FAILED;
    toggleFailedBtn.addEventListener('click', function() {
      failedOnly = !failedOnly;
      applyFailedFilter(failedOnly);
      toggleFailedBtn.textContent = failedOnly ? SHOW_ALL : SHOW_FAILED;
    });
  }

  // Hide every non-failed test row and any suite with no failed tests.
  function applyFailedFilter(enabled) {
    var suites = document.getElementsByClassName('suite');
    for (var s = 0; s < suites.length; s++) {
      var rows = suites[s].querySelectorAll('.suite-tests-table tbody tr');
      var failedInSuite = 0;
      for (var r = 0; r < rows.length; r++) {
        var isFailed = rows[r].classList.contains('failed');
        if (isFailed) {
          failedInSuite++;
        }
        rows[r].style.display = (enabled && !isFailed) ? 'none' : '';
      }
      suites[s].style.display = (enabled && failedInSuite === 0) ? 'none' : '';
    }
  }
})();
