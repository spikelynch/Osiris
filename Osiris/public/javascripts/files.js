/* Ajax callbacks for file browsing */


function files_browse(event) {
   var id = this.id.substr(3);
   if( $(this).data("open") ) {
       $("#files" + id).remove();
       $(this).data("open", false);
   } else {
       $(this).append('<div class="files" id="files' + id + '"></div>');
       $.getJSON('/files/' + id, function(data) { files_show(id, data) })
       $(this).data("open", true);
   }
}

function files_show(id, data) {
    var elt = $("#files" + id);

    console.log(data.length);
    console.log(data.inputs.length);
    console.log(data.outputs.length);
    console.log(data.other.length);

    files_links(elt, 'Inputs', data.inputs);

    files_links(elt, 'Outputs', data.outputs);

    files_links(elt, 'Other', data.other);
}


function files_links(elt, header, files) {
    elt.append('<div class="fhead">' + header + '</div>');
    for ( var p in files ) {
        for ( var i in files[p] ) {
            var file = files[p][i];
            elt.append('<div class="file">' + file + '</div>');
        }
    }
}
    

    




