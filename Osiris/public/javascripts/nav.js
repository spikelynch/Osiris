/* javascript helpers for the navigation menu */

function navtogglejobs(event) {
    var elt = $(this);
    if( elt.data('status') == 'open' ) {
        $('#myjobs li.job').remove();
        elt.data('status', 'closed');
    } else {
        $.getJSON(
            '/jobs',
            function(jobs) {
                for ( var id in jobs ) {
                    $('#myjobs').append('<li class="job"><a href="/job/' + id + '">' + jobs[id].label + '</a></li>');
                }
                elt.data('status', 'open');
            }
        );
    }
}
