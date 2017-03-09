# CR_PolygonsFromLines

Simple procedure creating polygons from multiple intersecting and closed lines


Version alpha 
- no error handling
- needs lines correctly intersected

Usage:

    drop table if exists test_lines_poly;
    select CR_PolygonsFromLines('test_lines','test_lines_poly');

test_lines - table with source data
test_lines_poly - created table with polygons

Included some sample data for tests.
