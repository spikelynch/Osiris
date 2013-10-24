// Guards code

// bind_guards(param, guards)

// bind a hash of guard settings to a single form field.

function bind_guards(param, guards) {
    var id = "#field_" + param
    var input_elt = $(id);
    $(id).data("guards", guards);
    $(id).focusout(function(e) { apply_guards(this)});
    $(id).change(function(e) { apply_guards(this)});
}

// shortcut to jquery for an input element by param name

function input(p) {
    var s = "input[name=" + p + "]";
    var elt = $(s);
    console.log(s + ": " + elt);
    return elt;
}


function guard_event(event) {
    apply_guards(this);
}


function apply_all_guards(form) {
    var valid = true;
    $('input').each(function() {
        if( this.name.substr(-4) == '_alt' ) {
            console.log("Skipping " + this.name);
            return;
        } else {
            console.log("Applying guards to " + this.name); 
        }
        if( !apply_guards(this) ) {
            console.log("...failed");
            valid = false;
        }
    });
    return valid;
}
        


function apply_guards(elt) {
    var p = elt.name;
    var val = elt.value;
    var g = $(elt).data("guards");

    console.log("Applying guards to " + p);

    if( !g ) {
        console.log('... no guards');
        return true;
    }


    
    // use the alt filebrowser value if it is set
    
    if( g.input_file ) {
        var pid = elt.id;
        var alt = $('#' + pid + '_alt');
        if( alt ) {
            if( alt.val() ) {
                val = alt.val();
            }
        }
    }


    console.log("Running guards");

    var error = run_guards(g, val);

    if( error != '' ) {
        show_error(elt, error);
        return false;
    } else {
        hide_error(elt);
        return true;
    }
}



function run_guards(g, val) {

    console.log("Value = " + val);

    //FIXME
    if( g.filepattern ) {
        console.log("Filepattern " + g.filepattern);
        var re = new RegExp(g.filepattern, 'i');
        if( !val.match(re) ) {
            return "Filename must match " + g.label;
        }
    }

    if( g.type == 'integer' ) {
        console.log("Type = integer");
        if( ! is_integer(val) ) {
            return "Must be an integer.";
        }
    }

    if( g.type == 'double' ) {
        console.log("Type = double");
        if( ! is_double(val) ) {
            return "Must be a number.";
        }
    }


    if( g.inclusions ) {
        console.log("Inclusions");
        if( g.inclusions[val] ) {
            for( var i in g.inclusions[val] ) {
                apply_guards($("#field_" + g.inclusions[val][i])[0]);
            }
        }
    }

    if( g.exclusions ) {
        console.log("Exclusions");
        if( g.exclusions[val] ) {
            for( var i in g.exclusions[val] ) {
                apply_guards($("#field_" + g.exclusions[val][i])[0]);
            }
        }
    }


    return "";
}





function is_integer(v) {
    var parsed = parseInt(v, 10);
    if( !isNaN(v) && v == parsed ){
        return 1;
    }
    return 0;
}

function is_double(v) {
    var parsed = parseFloat(v);
    if( !isNaN(v) && v == parsed ) {
        return 1;
    }
    return 0;
}







function show_error(elt, error) {
    $(elt).addClass("error_highlight");
    var param = $(elt).attr('name');
    var error_div = $("#error_" + param);
    error_div.empty();
    error_div.append(error);
    error_div.show();
}


function hide_error(elt) {
    $(elt).removeClass("error_highlight");
    var param = $(elt).attr('name');
    var error_div = $("#error_" + param);
    error_div.hide();
    error_div.empty();
}

    
