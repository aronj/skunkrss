$('input').on('input', function (e){
  $(this).next().attr('href', $(this).data('baseurl') + $(this).val())
})