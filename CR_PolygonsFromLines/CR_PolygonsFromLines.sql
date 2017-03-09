-- Function: public.cr_polygonsfromlines(text, text)

-- DROP FUNCTION public.cr_polygonsfromlines(text, text);

CREATE OR REPLACE FUNCTION public.cr_polygonsfromlines(
    in_table text,
    out_table text)
  RETURNS void AS
$BODY$
declare
  debug int;
  loading_query text;
  writing_query text;
  cnt int;
  cnt_collect int;
  collected record;
  tmp_members int[];
  tmp_members_add int[];
  tmp_cutting int[];
  i record;  

begin

debug = 1;

if debug = 0 then
  SET client_min_messages TO warning;
else
  SET client_min_messages TO notice; 
end if;

-- temporary table for input data
drop table if exists tmp_crpol_in;
loading_query = 'create temporary table tmp_crpol_in as select * from '||in_table||';';
execute loading_query;

if debug = 1 then
  GET DIAGNOSTICS cnt = ROW_COUNT;
  raise notice 'Input records: %',cnt;
end if;

-- temporary table for processed data
drop table if exists tmp_crpol_med;
create temporary table tmp_crpol_med (id serial, members int[], geom geometry);

-- case 1 - line is closed

insert into tmp_crpol_med (members, geom)
  select array[id]::int[],st_MakePolygon(geom) from tmp_crpol_in where ST_NPoints(geom) > 2 and ST_LineInterpolatePoint(geom, 0) = ST_LineInterpolatePoint(geom, 1);

if debug = 1 then
  GET DIAGNOSTICS cnt = ROW_COUNT;
  raise notice 'Closed lines: %',cnt;
end if;

delete from tmp_crpol_in a where exists (select 1 from tmp_crpol_med b where a.id = any (b.members));

-- case 2 - collecting lines

while (select count(1) from tmp_crpol_in a where exists (select 1 from tmp_crpol_in b where ST_Intersects(a.geom, b.geom) and a.id!=b.id))>0
loop
  select array[id]::int[] from tmp_crpol_in a order by id limit 1 into tmp_members;
  <<collecting>>
  loop
    select array_agg(id) as id, ST_Union(geom) as geom from tmp_crpol_in where id=any(tmp_members) into collected;   
    select array_agg(id) from tmp_crpol_in a where ST_Intersects(a.geom,collected.geom) and not a.id = any(collected.id) into tmp_members_add;
    exit collecting when tmp_members_add is null;
    if debug = 1 then Raise notice 'Adding member % into %',tmp_members_add,tmp_members;end if;
    tmp_members=tmp_members||tmp_members_add;
  end loop;
  insert into tmp_crpol_med (members, geom)
    select tmp_members, ST_LineMerge(ST_Union(geom)) from tmp_crpol_in where id = any (tmp_members);
  delete from tmp_crpol_in where id = any (tmp_members);
  cnt_collect = cnt_collect+1;  
end loop;

if debug = 1 then
  Raise notice 'Collected geoms: %',cnt_collect;
end if;

update tmp_crpol_med set geom = ST_MakePolygon(geom) where ST_IsClosed(geom) and ST_GeometryType(geom)='ST_LineString';

if debug = 1 then
  GET DIAGNOSTICS cnt = ROW_COUNT;
  Raise notice 'Closed geoms: %',cnt;
end if;

-- cutting holes in geoms 

drop table if exists tmp_holes;
create temporary table tmp_holes as 
  select id,array_agg(0-holes) as holes,array_agg(hole_id) as hole_id, ST_Union(geom) as geom from (
    select a.id, unnest(b.members) as holes,b.id as hole_id, b.geom as geom
    from tmp_crpol_med a
    join tmp_crpol_med b on ST_CoveredBy(b.geom, a.geom) and a.id!=b.id
    ) as aa
  group by 1;

if debug = 1 then
  GET DIAGNOSTICS cnt = ROW_COUNT;
  Raise notice 'Geoms with holes: %',cnt;
end if;

for i in select * from tmp_holes
loop
  update tmp_crpol_med 
  set geom = ST_Difference(geom,i.geom),
    members = members||i.holes 
  where id = i.id;
end loop;

-- deleting holes from geometries table

delete from tmp_crpol_med a where exists (select 1 from tmp_holes b where a.id = any(b.hole_id));

if debug = 1 then
  GET DIAGNOSTICS cnt = ROW_COUNT;
  Raise notice 'Deleted holes: %',cnt;
end if;

--writing polygon table

writing_query = 'create table '||out_table||' as select * from tmp_crpol_med where ST_GeometryType(geom)=''ST_Polygon'';';
execute writing_query;

Return;
end;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION public.cr_polygonsfromlines(text, text)
  OWNER TO postgres;
