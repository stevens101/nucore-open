/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
// Requires a data-attribute `form` which is a selector for the search form to submit
// The form requires an email and a format field (hidden).
class ExportCsvReport {
  constructor(selector) {
    this.selector = selector;
  }

  init() {
    return $(document).on("click", this.selector, this.exportAllClicked);
  }

  exportAllClicked(event) {
    event.preventDefault();

    const $form = $($(event.target).data('form'));
    const $emailField = $form.find('[name=email]');
    const defaultEmail = $emailField.val();

    const toAddress = prompt('Have the report emailed to this address:', defaultEmail);

    if (toAddress) {
      $emailField.val(toAddress);
      $form.find('[name=format]').val('csv').prop('disabled', false);
      $emailField.prop('disabled', false);

      // Do an ajax request so we don't need to re-render this search page
      $.ajax({
        type: $form.attr('method'),
        url: $form.attr('action'),
        data: $form.serialize()
      }).success(responseText => Flash.info(responseText));

      // since the submit doesn't reload the page when you download the CSV, we need
      // to reset format so the normal search submit works properly
      $form.find('[name=format]').val(null).prop('disabled', true);
      return $emailField.prop('disabled', true);
    }
  }
}

$(() => new ExportCsvReport('.js--exportSearchResults').init());
