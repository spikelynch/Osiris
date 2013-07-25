/* Ajax callbacks for file browsing */

/* filebrowser_init(s) - bid is the id of the containing element.
   selected is a function to be called when the user selects a file. 
   It should take two arguments - jobid and filename */

function filebrowser_init(bid, ctrlid, selected) {
    var elt = $('#' + bid);
    elt.empty();
    elt.addClass('filebrowser');
    elt.data("selected", selected);
    elt.data("status", "closed");
    $('#' + ctrlid).click(function (event) {
        filebrowser(event, bid);
    });
}

/* filebrowser - open or close a filebrowser's job list */

function filebrowser(event, bid) {
    var elt = $(this);
    var browser = $('#' + bid);
    if( browser.data("status") == "closed" ) {
        $.getJSON(
            '/jobs',
            function(jobs) {
                for ( var jid in jobs ) {
                    var id = bid + '_' + jid;
                    browser.append('<div class="filebrowser_job" id="' + id + '">Job ' + jid + ': ' + jobs[jid].appname + '</div>');
                    $('#' + id).click(filebrowser_job).data("jid", jid);
                }
                browser.data("status", "open");
            }
        );
    } else {
        browser.empty();
        browser.data("status", "closed");
    }
}

/* filebrowser_job: opens or closes a job's file list */

function filebrowser_job(event) {
    event.stopPropagation();
    var fb = $(this).parent();
    var bid = fb.attr("id");
    var jid = $(this).data("jid");
    var id = bid + '_' + jid;
    var fid = id + "_files";
    if( $(this).data("open") ) {
        $("#" + fid).remove();
        $(this).data("open", false);
    } else {
        $(this).after('<div class="files" id="' + fid + '"></div>');
        $.getJSON('/files/' + jid, function(data) {
            filebrowser_files(id, data)
        });
        $(this).data("open", true);
    }
    return false;
}

/* filebrowser_files - write each set of files (Input / Output) */

function filebrowser_files(id, data) {
    var elt = $("#" + id);
    filebrowser_filelist(elt, id, 'Inputs', data.inputs);
    filebrowser_filelist(elt, id, 'Outputs', data.outputs);
    elt.children('.file').click(filebrowser_select);
}


/* filebrowser_filelist - write a list of files */

function filebrowser_filelist(elt, id, header, files) {
    elt.append('<div class="fhead">' + header + '</div>');
    for ( var p in files ) {
        for ( var i in files[p] ) {
            var file = files[p][i];
            var fileid = id + '_' + file;
            elt.append('<div class="file" id="' + fileid + '">' + p + '=' + file + '</div>');
            
        }
    }
}
    

/* filebrowser_select - called when a filename is clicked */

function filebrowser_select(event) {
    event.stopPropagation();
    var fileid = $(this).attr('id');
    var targetid = event.target.id;
    var browser = $(this).parents('.filebrowser');
    
    browser.find('.file').removeClass('selected');
    $(this).addClass('selected');
    var selected = browser.data('selected');
    if( selected ) {
        // browserID_files_filename
        var fields = fileid.split('_');
        
        selected(fields[1], fields[2]);
    }
}




