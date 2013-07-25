/* Ajax callbacks for file browsing */

/* filebrowser_init(s) - bid is the id of the containing element.
   selected is a function to be called when the user selects a file. 
   The function gets the list of jobs with an ajax call. */

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
            filebrowser_files(fid, data)
        });
        $(this).data("open", true);
    }
    return false;
}


function filebrowser_files(fid, data) {
    var elt = $("#" + fid);
    filebrowser_filelist(elt, fid, 'Inputs', data.inputs);
    filebrowser_filelist(elt, fid, 'Outputs', data.outputs);
    elt.children('.file').click(filebrowser_select);
    elt.children('.file').each(function() { "Files: " + $(this).attr('id')});
}


function filebrowser_filelist(elt, fid, header, files) {
    elt.append('<div class="fhead">' + header + '</div>');
    for ( var p in files ) {
        for ( var i in files[p] ) {
            var file = files[p][i];
            var fileid = fid + '_' + file;
            console.log("Added " + fileid);
            elt.append('<div class="file" id="' + fileid + '">' + p + '=' + file + '</div>');
            
        }
    }
}
    

function filebrowser_select(event) {
    event.stopPropagation();
    var fileid = $(this).attr('id');
    var targetid = event.target.id;
    // find the owning filebrowser and call the "selected" hook
    console.log("filebrowser_select thisid = " + fileid);
    console.log("target id = " + targetid);
    var browser = $(this).parent('.filebrowser');
}




