/***
 * Upates the file count when result files are uploaded or removed
 * via modal on the admin facility Order show page.
***/

document.addEventListener("DOMContentLoaded", function() {

  function fetchAndRefresh() {
    const table = document.getElementsByClassName("js--orderTableRefresh")[0];
    const url = new URL(document.location);

    url.searchParams.set("refresh", "true");
    const headers = { Accept: "text/html" };

    fetch(url, { headers: headers })
    .then(function (response) {
      if (response.ok) {
        response.text()
        .then(function(body) {
          table.innerHTML = body;
          setResultsFileUploadModals()
         });
      }
    });
  }

  function setResultsFileUploadModals() {
    new AjaxModal('a.results-file-upload', '#results-file-upload-modal', {
      loading_text: 'Loading Results Files...',
      success(modal) {
        return $('.modal a.remove-file').bind('ajax:complete', function(e) {
          e.preventDefault();
          return modal.reload();
        });
      }
    })
  }

  setResultsFileUploadModals();
  $("#results-file-upload-modal").on("hidden", fetchAndRefresh);

});
